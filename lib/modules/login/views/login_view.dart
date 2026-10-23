import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/primary_button.dart';
import '../../signup/widgets/social_button.dart';
import '../view_model/login_view_model.dart';
import '../widgets/login_text_field.dart';

class LoginView extends GetView<LoginViewModel> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TopBar(),
              const SizedBox(height: 16),
              const _HeroCard(),
              const SizedBox(height: 24),
              const FieldLabel(
                icon: Icons.badge_outlined,
                text: 'Email Address',
              ),
              const SizedBox(height: 6),
              LoginTextField(
                controller: controller.emailController,
                icon: Icons.mail_outline,
                hint: 'e.g. sarah@familycare.org',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const FieldLabel(icon: Icons.lock_outline, text: 'Password'),
                  GestureDetector(
                    onTap: controller.forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Obx(
                () => LoginTextField(
                  controller: controller.passwordController,
                  icon: Icons.key,
                  hint: 'Enter your security passkey',
                  obscureText: controller.obscurePassword.value,
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: IconButton(
                      onPressed: controller.togglePasswordVisibility,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        controller.obscurePassword.value
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 22,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Obx(
                () => _RememberMe(
                  checked: controller.rememberMe.value,
                  onTap: controller.toggleRememberMe,
                ),
              ),
              const SizedBox(height: 20),
              Obx(
                () => PrimaryButton(
                  label: 'Sign In',
                  loading: controller.isLoading.value,
                  onPressed: controller.signIn,
                ),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(9999)),
                  boxShadow: AppTheme.shadowSm,
                ),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      foregroundColor: AppColors.onSurface,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: controller.signInWithBiometrics,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 22,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Sign in with Face ID / Fingerprint',
                          style: AppTextStyles.labelMd,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => SocialButton.google(
                  label: 'Continue with Google',
                  loading: controller.isGoogleLoading.value,
                  onTap: controller.signInWithGoogle,
                ),
              ),
              const SizedBox(height: 24),
              const _TrustBanner(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account?",
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: controller.signUp,
                    child: Text(
                      'Sign Up',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Material(
          color: AppColors.surfaceContainerLow,
          shape: const CircleBorder(),
          elevation: 0.5,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: Get.back,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.arrow_back,
                size: 24,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(9999),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medication,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                AppStrings.appName,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.primary,
                  letterSpacing: -0.025 * 18,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 176,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surfaceContainer),
                Image.asset('assets/login.png', fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppColors.surfaceContainerLow,
                        AppColors.surfaceContainerLow.withValues(alpha: 0),
                        AppColors.surfaceContainerLow.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user,
                        size: 14,
                        color: AppColors.onPrimaryFixedVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Gentle Routine Care',
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onPrimaryFixedVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome Back to ${AppStrings.appName}',
                  style: AppTextStyles.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                    letterSpacing: -0.025 * 24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in to access your medication routine, reminders, and caregiver circle.',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RememberMe extends StatelessWidget {
  const _RememberMe({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: checked
                      ? AppColors.primary
                      : AppColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                  boxShadow: AppTheme.shadowSm,
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 150),
                  scale: checked ? 1 : 0,
                  child: const Icon(
                    Icons.check,
                    size: 16,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Remember me on this device',
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _TrustBanner extends StatelessWidget {
  const _TrustBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protected Care Record',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Your health records remain private and stored securely.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
