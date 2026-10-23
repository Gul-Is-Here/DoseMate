import 'dart:async';

import 'package:get/get.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';

class VerifyEmailViewModel extends GetxController {
  static const _resendCooldown = 60;

  final _auth = Get.find<AuthService>();

  final isChecking = false.obs;
  final isResending = false.obs;

  /// Seconds until another verification email may be sent. Starts full
  /// because one was just sent at sign up.
  final resendIn = _resendCooldown.obs;

  Timer? _timer;

  String get email => _auth.user.value?.email ?? '';

  @override
  void onInit() {
    super.onInit();
    _startCooldown();
  }

  Future<void> checkVerified() async {
    if (isChecking.value) return;
    isChecking.value = true;
    try {
      final verified = await _auth.repository.reloadEmailVerified();
      _auth.refreshUser();
      if (verified) {
        _auth.goToRouteForUser();
      } else {
        Get.snackbar(
          'Not verified yet',
          'Open the link in the email we sent, then try again.',
        );
      }
    } on AuthFailure catch (e) {
      Get.snackbar('Something went wrong', e.message);
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> resend() async {
    if (isResending.value || resendIn.value > 0) return;
    isResending.value = true;
    try {
      await _auth.repository.sendEmailVerification();
      _startCooldown();
      Get.snackbar('Email sent', 'A new verification link was sent to $email.');
    } on AuthFailure catch (e) {
      Get.snackbar('Something went wrong', e.message);
    } finally {
      isResending.value = false;
    }
  }

  Future<void> signOut() => _auth.signOut();

  void _startCooldown() {
    _timer?.cancel();
    resendIn.value = _resendCooldown;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (--resendIn.value <= 0) timer.cancel();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
