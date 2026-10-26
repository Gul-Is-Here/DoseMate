import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../widgets/app_snackbar.dart';

class VerifyEmailViewModel extends GetxController with WidgetsBindingObserver {
  static const resendCooldown = 60;

  final _auth = Get.find<AuthService>();

  final isChecking = false.obs;
  final isResending = false.obs;

  /// Whether a verification email is known to have gone out. False when the
  /// one at sign up failed, null when unknown (e.g. after signing in again).
  final emailSent = RxnBool();

  /// Seconds until another verification email may be sent.
  final resendIn = 0.obs;

  Timer? _timer;

  String get email => _auth.user.value?.email ?? '';

  @override
  void onInit() {
    super.onInit();
    emailSent.value = _auth.verificationEmailSent;
    _auth.verificationEmailSent = null;
    // Only a send that actually happened starts the wait.
    if (emailSent.value == true) _startCooldown();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onReady() {
    super.onReady();
    if (emailSent.value == false) {
      showSnack(
        "Couldn't send the verification email",
        'Your account was created. Tap Resend Email to try again.',
      );
    }
  }

  /// Coming back from the email app or browser: check without nagging.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkVerified(silent: true);
  }

  /// Reloads the Firebase user; moves on only once Firebase confirms the
  /// email is verified.
  Future<void> checkVerified({bool silent = false}) async {
    if (isChecking.value) return;
    isChecking.value = true;
    try {
      final verified = await _auth.repository.reloadEmailVerified();
      _auth.refreshUser();
      if (verified) {
        await _auth.completeSignIn();
      } else if (!silent) {
        showSnack(
          'Not verified yet',
          'Open the link in the email we sent, then try again.',
        );
      }
    } on AuthFailure catch (e) {
      if (!silent) showSnack("Couldn't check verification", e.message);
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> resend() async {
    if (isResending.value || resendIn.value > 0) return;
    isResending.value = true;
    try {
      await _auth.repository.sendEmailVerification();
      emailSent.value = true;
      _startCooldown();
      showSnack('Email sent', 'A new verification link was sent to $email.');
    } on AuthFailure catch (e) {
      // Firebase is throttling: wait before allowing another try.
      if (e.code == 'too-many-requests') _startCooldown();
      showSnack("Couldn't send email", e.message);
    } finally {
      isResending.value = false;
    }
  }

  Future<void> signOut() => _auth.signOut();

  void _startCooldown() {
    _timer?.cancel();
    resendIn.value = resendCooldown;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (--resendIn.value <= 0) timer.cancel();
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.onClose();
  }
}
