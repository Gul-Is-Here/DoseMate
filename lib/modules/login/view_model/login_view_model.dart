import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../widgets/app_snackbar.dart';

class LoginViewModel extends GetxController {
  final _auth = Get.find<AuthService>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final obscurePassword = true.obs;
  final rememberMe = true.obs;
  final isLoading = false.obs;
  final isGoogleLoading = false.obs;
  final isResetLoading = false.obs;

  bool get _busy =>
      isLoading.value || isGoogleLoading.value || isResetLoading.value;

  void togglePasswordVisibility() => obscurePassword.toggle();

  void toggleRememberMe() => rememberMe.toggle();

  Future<void> signIn() async {
    if (_busy) return;
    final email = emailController.text.trim();
    final password = passwordController.text;
    final error = Validators.email(email) ?? Validators.loginPassword(password);
    if (error != null) return _showError(error);

    await _run(isLoading, () async {
      await _auth.repository.signInWithEmail(email: email, password: password);
      passwordController.clear();
      await _auth.completeSignIn();
    });
  }

  Future<void> signInWithGoogle() async {
    if (_busy) return;
    await _run(isGoogleLoading, () async {
      final isNewUser = await _auth.repository.signInWithGoogle();
      await _auth.completeSignIn(isNewAccount: isNewUser);
    });
  }

  Future<void> forgotPassword() async {
    if (_busy) return;
    final email = emailController.text.trim();
    final error = Validators.email(email);
    if (error != null) {
      return _showError(
        'Enter your email above, then tap "Forgot password?" again.',
      );
    }
    await _run(isResetLoading, () async {
      await _auth.repository.sendPasswordReset(email);
      showSnack(
        'Check your inbox',
        'If an account exists for $email, a password reset link is on its way.',
      );
    });
  }

  void signUp() => Get.offNamed(AppRoutes.signup);

  Future<void> _run(RxBool flag, Future<void> Function() action) async {
    flag.value = true;
    try {
      await action();
    } on AuthCancelled {
      // User closed the Google sheet; nothing to report.
    } on AuthFailure catch (e) {
      _showError(e.message);
    } finally {
      flag.value = false;
    }
  }

  void _showError(String message) => showSnack('Sign in failed', message);

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
