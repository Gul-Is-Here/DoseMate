import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/primary_button.dart';
import '../view_model/signup_view_model.dart';
import '../widgets/account_for_selector.dart';
import '../widgets/signup_text_field.dart';
import '../widgets/social_button.dart';
import '../../../widgets/app_logo.dart';

class SignupView extends GetView<SignupViewModel> {
  const SignupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TopBar(),
              const SizedBox(height: 8),
              const _HeroCard(),
              const SizedBox(height: 24),
              Text(
                'Create Your ${AppStrings.appName} Account',
                style: AppTextStyles.headlineLgMobile.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Join thousands managing medications and medical appointments '
                'with gentle peace of mind.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Obx(
                () => AccountForSelector(
                  selected: controller.accountFor.value,
                  onChanged: controller.selectAccountFor,
                ),
              ),
              const SizedBox(height: 16),
              SignupTextField(
                label: 'Full Name',
                controller: controller.nameController,
                icon: Icons.badge_outlined,
                hint: 'Eleanor Vance',
              ),
              const SizedBox(height: 16),
              SignupTextField(
                label: 'Email Address',
                controller: controller.emailController,
                icon: Icons.mail_outline,
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              Obx(
                () => SignupTextField(
                  label: 'Create Password',
                  controller: controller.passwordController,
                  icon: Icons.lock_outline,
                  hint: 'At least 8 letters & numbers',
                  obscureText: controller.obscurePassword.value,
                  onToggleObscure: controller.togglePasswordVisibility,
                ),
              ),
              const SizedBox(height: 16),
              Obx(
                () => SignupTextField(
                  label: 'Confirm Password',
                  controller: controller.confirmPasswordController,
                  icon: Icons.lock_outline,
                  hint: 'Re-enter your password',
                  obscureText: controller.obscurePassword.value,
                ),
              ),
              const SizedBox(height: 20),
              Obx(
                () => PrimaryButton(
                  label: 'Create Free Account',
                  iconSize: 18,
                  loading: controller.isLoading.value,
                  onPressed: controller.createAccount,
                ),
              ),
              const SizedBox(height: 24),
              const _OrDivider(),
              const SizedBox(height: 24),
              // One sign-in per platform: Google on Android, Apple on iOS.
              if (defaultTargetPlatform == TargetPlatform.iOS)
                SocialButton.apple(onTap: controller.signUpWithApple)
              else
                Obx(
                  () => SocialButton.google(
                    loading: controller.isGoogleLoading.value,
                    onTap: controller.signUpWithGoogle,
                  ),
                ),
              const SizedBox(height: 24),
              const _PrivacyNote(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account?',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: controller.signIn,
                      child: Text(
                        'Sign In',
                        style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: AppColors.surfaceContainerLow,
            shape: const CircleBorder(),
            elevation: 0.5,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: Get.back,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
          const AppLogo(size: 40),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/signup.png', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  // A dark scrim over the photo in either theme.
                  colors: const [
                    Color(0x80191B2A),
                    Color(0x00191B2A),
                    Color(0x00191B2A),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest.withValues(
                    alpha: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(9999),
                  boxShadow: AppTheme.shadowSm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Trusted by 65,000+ families',
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: AppColors.surfaceContainerHigh),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR FAST SIGN UP WITH',
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
              letterSpacing: 0.05 * 12,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

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
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.shield_outlined,
              size: 18,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safe, Private & HIPAA-Conscious',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "By continuing, you agree to ${AppStrings.appName}'s Terms of Service "
                  'and Privacy Policy. We hold all medical routines in highest '
                  'confidence and never sell your personal health records.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.625,
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
