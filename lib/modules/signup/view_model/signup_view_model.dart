import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/validators.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';

enum AccountFor { myself, caregiver }

class SignupViewModel extends GetxController {
  final _auth = Get.find<AuthService>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final accountFor = AccountFor.myself.obs;
  final obscurePassword = true.obs;
  final isLoading = false.obs;
  final isGoogleLoading = false.obs;

  bool get _busy => isLoading.value || isGoogleLoading.value;

  void selectAccountFor(AccountFor value) => accountFor.value = value;

  void togglePasswordVisibility() => obscurePassword.toggle();

  Future<void> createAccount() async {
    if (_busy) return;
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final error =
        Validators.name(name) ??
        Validators.email(email) ??
        Validators.newPassword(password) ??
        Validators.confirmPassword(password, confirmPasswordController.text);
    if (error != null) return _showError(error);

    await _run(isLoading, () async {
      await _auth.repository.signUpWithEmail(
        name: name,
        email: email,
        password: password,
      );
      passwordController.clear();
      confirmPasswordController.clear();
      _auth.goToRouteForUser();
    });
  }

  Future<void> signUpWithGoogle() async {
    if (_busy) return;
    await _run(isGoogleLoading, () async {
      await _auth.repository.signInWithGoogle();
      _auth.goToRouteForUser();
    });
  }

  // TODO: add Sign in with Apple (needs an Apple Developer account).
  void signUpWithApple() =>
      Get.snackbar('Coming soon', 'Sign in with Apple is not available yet.');

  void signIn() => Get.offNamed(AppRoutes.login);

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

  void _showError(String message) =>
      Get.snackbar("Couldn't create account", message);

  @override
  void onClose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
