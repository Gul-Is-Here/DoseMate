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

  /// Set by sign up for the Verify Email screen: whether the first
  /// verification email went out.
  bool? verificationEmailSent;

  /// The sign up choice, kept while the email is verified so Profile Setup
  /// still preselects it.
  AccountFor? pendingAccountFor;

  /// Signed in but not yet allowed past Verify Email.
  bool get needsVerification {
    final current = user.value;
    return current != null && AuthRepository.needsEmailVerification(current);
  }

  /// Waits for Firebase to restore any persisted session before routing.
  Future<AuthService> init() async {
    user.value = await repository.authStateChanges().first;
    // Restored session: load the profile in the background so routing
    // isn't delayed; screens update when it arrives.
    // Unverified accounts can't read their data yet; they load after
    // verification.
    if (user.value case final restored?
        when !AuthRepository.needsEmailVerification(restored)) {
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
  /// email accounts always verify first, new or not; then new accounts and
  /// incomplete profiles see Profile Setup, and everyone else Home. A
  /// restart with a saved session skips the profile check, so a skipped
  /// profile is offered again on the next sign in.
  Future<String> routeAfterSignIn({bool isNewAccount = false}) async {
    final current = user.value ?? repository.currentUser;
    if (current == null) return AppRoutes.login;
    if (AuthRepository.needsEmailVerification(current)) {
      return AppRoutes.verifyEmail;
    }
    // Profiles load in every case, so setup and Home have them ready. Errors
    // are shown by those screens; they never block sign in.
    final loading = profiles.start(
      current.uid,
      selfName: selfNameFor(current),
      force: true,
    );
    if (isNewAccount) return AppRoutes.profileSetup;
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
    if (accountFor != null) pendingAccountFor = accountFor;
    // The auth stream may report this sign in after we navigate; the route
    // guards read [user], so take Firebase's current user now.
    if (repository.currentUser case final current?) user.value = current;
    final route = await routeAfterSignIn(isNewAccount: isNewAccount);
    final choice = pendingAccountFor;
    if (route != AppRoutes.verifyEmail) pendingAccountFor = null;
    Get.offAllNamed(
      route,
      arguments: route == AppRoutes.profileSetup ? choice : null,
    );
  }

  /// Re-reads the user after [User.reload], which authStateChanges doesn't report.
  void refreshUser() {
    user.value = repository.currentUser;
    user.refresh();
  }

  /// Run before signing out while the account can still write, e.g. to
  /// remove this device's alert registration. Failures don't stop it.
  final beforeSignOut = <Future<void> Function()>[];

  Future<void> signOut() async {
    await _runSteps(beforeSignOut);
    await repository.signOut();
  }

  static Future<void> _runSteps(List<Future<void> Function()> steps) async {
    for (final step in List.of(steps)) {
      try {
        await step().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Signing out must always work.
      }
    }
  }

  /// Stops everything that follows the account's data (profiles, and the
  /// care records, alarms and screens that follow them) while the server
  /// deletes it, so nothing on this device writes it back: an empty
  /// account would otherwise get a new Myself profile.
  void pauseAccountSync() => profiles.stop();

  /// Undoes [pauseAccountSync] when deletion didn't go through.
  Future<void> resumeAccountSync() async {
    final current = user.value;
    if (current == null || profiles.uid != null) return;
    await profiles.start(current.uid, selfName: selfNameFor(current));
  }

  /// Run after the server deleted the account, while still signed in on
  /// this device: forget what this device kept for it (e.g. its cached
  /// records and per-account settings). Failures don't stop it.
  final afterAccountDeleted = <Future<void> Function(String uid)>[];

  /// The account is gone on the server: clear its alarms, notifications
  /// and push registration, remove its local data, revoke Google access
  /// and sign out. Sign in then opens through [_onAuthChanged].
  Future<void> finishAccountDeletion() async {
    final uid = user.value?.uid;
    pauseAccountSync();
    await _runSteps(beforeSignOut);
    if (uid != null) {
      await _runSteps([
        for (final step in afterAccountDeleted) () => step(uid),
      ]);
    }
    await repository.signOut(revokeGoogle: true);
  }

  void _onAuthChanged(User? next) {
    final wasSignedIn = user.value != null;
    user.value = next;
    // Covers explicit logout and sessions revoked elsewhere.
    if (wasSignedIn && next == null) {
      verificationEmailSent = null;
      pendingAccountFor = null;
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
