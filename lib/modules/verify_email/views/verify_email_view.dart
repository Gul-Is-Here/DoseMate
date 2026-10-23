import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../widgets/primary_button.dart';
import '../view_model/verify_email_view_model.dart';

class VerifyEmailView extends GetView<VerifyEmailViewModel> {
  const VerifyEmailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_unread,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineLgMobile.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => Text(
                  'We sent a verification link to ${controller.email}. '
                  'Open it, then come back and tap the button below.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Obx(
                () => PrimaryButton(
                  label: "I've Verified My Email",
                  loading: controller.isChecking.value,
                  onPressed: controller.checkVerified,
                ),
              ),
              const SizedBox(height: 8),
              Obx(() {
                final wait = controller.resendIn.value;
                return SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      foregroundColor: AppColors.onSurface,
                      disabledBackgroundColor: AppColors.surfaceContainerLow,
                      disabledForegroundColor: AppColors.outline,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: wait > 0 || controller.isResending.value
                        ? null
                        : controller.resend,
                    child: Text(
                      wait > 0 ? 'Resend email in ${wait}s' : 'Resend Email',
                      style: AppTextStyles.labelLg,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: controller.signOut,
                  child: Text(
                    'Use a different account',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
