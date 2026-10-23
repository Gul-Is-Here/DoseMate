import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../repositories/auth_repository.dart';

/// App-wide session state. Firebase Auth is the source of truth; this mirrors
/// it in a single listener and decides where the user belongs.
class AuthService extends GetxService {
  AuthService(this.repository);

  final AuthRepository repository;
  final user = Rxn<User>();

  StreamSubscription<User?>? _subscription;

  /// Waits for Firebase to restore any persisted session before routing.
  Future<AuthService> init() async {
    user.value = await repository.authStateChanges().first;
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

  void goToRouteForUser() => Get.offAllNamed(routeForUser);

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
    if (wasSignedIn && next == null) Get.offAllNamed(AppRoutes.login);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
