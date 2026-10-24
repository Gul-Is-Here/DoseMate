import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import 'profile_service.dart';

/// App-wide session state. Firebase Auth is the source of truth; this mirrors
/// it in a single listener and decides where the user belongs.
class AuthService extends GetxService {
  AuthService(this.repository, this.profiles);

  final AuthRepository repository;
  final ProfileService profiles;
  final user = Rxn<User>();

  StreamSubscription<User?>? _subscription;

  /// Waits for Firebase to restore any persisted session before routing.
  Future<AuthService> init() async {
    user.value = await repository.authStateChanges().first;
    // Restored session: load the profile in the background so routing
    // isn't delayed; screens update when it arrives.
    if (user.value case final restored?) {
      profiles.start(restored.uid, selfName: selfNameFor(restored)).ignore();
    }
    _subscription = repository.authStateChanges().listen(_onAuthChanged);
    return this;
  }

  bool get isSignedIn => user.value != null;

  String get initialRoute => isSignedIn ? routeForUser : AppRoutes.onboarding;

  /// Where a signed-in user should land.
  String get routeForUser {
    final current = user.value;
    if (current == null) return AppRoutes.login;
    return AuthRepository.needsEmailVerification(current)
        ? AppRoutes.verifyEmail
        : AppRoutes.home;
  }

  /// Name for an automatically created Myself profile.
  static String selfNameFor(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email;
    return email == null ? 'Me' : email.split('@').first;
  }

  void goToRouteForUser() => Get.offAllNamed(routeForUser);

  /// Where to go right after a successful sign in or sign up. Unverified
  /// email accounts verify first; everyone else sees Profile Setup until
  /// their profile is complete. A restart with a saved session skips this
  /// check, so a skipped profile is offered again on the next sign in.
  Future<String> routeAfterSignIn({bool isNewAccount = false}) async {
    final current = user.value ?? repository.currentUser;
    if (current == null) return AppRoutes.login;
    // Profiles load in every case, so setup and Home have them ready. Errors
    // are shown by those screens; they never block sign in.
    final loading = profiles.start(
      current.uid,
      selfName: selfNameFor(current),
      force: true,
    );
    if (isNewAccount) return AppRoutes.profileSetup;
    if (AuthRepository.needsEmailVerification(current)) {
      return AppRoutes.verifyEmail;
    }
    await loading;
    // Can't tell whether setup is done: don't lock people out; they can
    // finish it later from the profile switcher.
    if (!profiles.isReady) return AppRoutes.home;
    return profiles.account.value.setupCompleted
        ? AppRoutes.home
        : AppRoutes.profileSetup;
  }

  /// Replaces the whole stack so back never returns to the auth screens.
  Future<void> completeSignIn({
    bool isNewAccount = false,
    AccountFor? accountFor,
  }) async {
    final route = await routeAfterSignIn(isNewAccount: isNewAccount);
    Get.offAllNamed(route, arguments: accountFor);
  }

  /// Re-reads the user after [User.reload], which authStateChanges doesn't report.
  void refreshUser() {
    user.value = repository.currentUser;
    user.refresh();
  }

  Future<void> signOut() => repository.signOut();

  void _onAuthChanged(User? next) {
    final wasSignedIn = user.value != null;
    user.value = next;
    // Covers explicit logout and sessions revoked elsewhere.
    if (wasSignedIn && next == null) {
      profiles.stop();
      Get.offAllNamed(AppRoutes.login);
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
