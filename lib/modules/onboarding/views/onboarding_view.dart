import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/onboarding_page.dart';
import '../view_model/onboarding_view_model.dart';
import '../widgets/dot_indicator.dart';
import '../widgets/feature_card.dart';
import '../widgets/feature_list_card.dart';
import '../widgets/onboarding_illustration.dart';
import '../widgets/page_indicator.dart';
import '../widgets/visit_illustration_card.dart';
import '../../../widgets/app_logo.dart';

class OnboardingView extends GetView<OnboardingViewModel> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Obx(
              () => switch (controller.currentIndex.value) {
                0 => _TopBar(onSkip: controller.skip),
                _ when controller.isLastPage => _FinalTopBar(
                  step: controller.currentIndex.value + 1,
                  count: controller.pages.length,
                  onBack: controller.previous,
                ),
                _ => _StepTopBar(
                  onBack: controller.previous,
                  onSkip: controller.skip,
                ),
              },
            ),
            Expanded(
              child: PageView.builder(
                controller: controller.pageController,
                itemCount: controller.pages.length,
                onPageChanged: controller.onPageChanged,
                itemBuilder: (_, index) => switch (index) {
                  0 => _OnboardingPageContent(
                    page: controller.pages[index],
                    index: index,
                    count: controller.pages.length,
                    onContinue: controller.next,
                    onExploreDemo: controller.exploreDemo,
                  ),
                  _ when index == controller.pages.length - 1 =>
                    _FinalPageContent(
                      page: controller.pages[index],
                      index: index,
                      count: controller.pages.length,
                      onGetStarted: controller.getStarted,
                      onLogin: controller.login,
                      onExploreDemo: controller.exploreDemo,
                    ),
                  _ => _StepPageContent(
                    page: controller.pages[index],
                    index: index,
                    count: controller.pages.length,
                    onContinue: controller.next,
                    onSignIn: controller.login,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AppLogo(size: 40),
          InkWell(
            onTap: onSkip,
            borderRadius: BorderRadius.circular(9999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'Skip',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageContent extends StatelessWidget {
  const _OnboardingPageContent({
    required this.page,
    required this.index,
    required this.count,
    required this.onContinue,
    required this.onExploreDemo,
  });

  final OnboardingPage page;
  final int index;
  final int count;
  final VoidCallback onContinue;
  final VoidCallback onExploreDemo;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      child: Column(
        children: [
          OnboardingIllustration(image: page.image, badge: page.badge),
          const SizedBox(height: 20),
          PageIndicator(count: count, current: index),
          const SizedBox(height: 20),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLgMobile.copyWith(
              color: AppColors.onSurface,
              letterSpacing: -0.025 * 24,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              page.description,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          if (page.features.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final (i, feature) in page.features.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              FeatureCard(feature: feature),
            ],
          ],
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: const StadiumBorder(),
                elevation: 1,
              ),
              onPressed: onContinue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue', style: AppTextStyles.labelLg),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onExploreDemo,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Explore Demo Mode',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalTopBar extends StatelessWidget {
  const _FinalTopBar({
    required this.step,
    required this.count,
    required this.onBack,
  });

  final int step;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: AppColors.surfaceContainerLow,
            shape: const CircleBorder(),
            elevation: 0.5,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onBack,
              child: SizedBox(
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
          const AppLogo(size: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              'Step $step of $count',
              style: AppTextStyles.labelSm.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalPageContent extends StatelessWidget {
  const _FinalPageContent({
    required this.page,
    required this.index,
    required this.count,
    required this.onGetStarted,
    required this.onLogin,
    required this.onExploreDemo,
  });

  final OnboardingPage page;
  final int index;
  final int count;
  final VoidCallback onGetStarted;
  final VoidCallback onLogin;
  final VoidCallback onExploreDemo;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      child: Column(
        children: [
          OnboardingIllustration.cover(image: page.image),
          const SizedBox(height: 16),
          DotIndicator(count: count, current: index),
          const SizedBox(height: 16),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLgMobile.copyWith(
              color: AppColors.onSurface,
              height: 1.375,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              page.description,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FeatureListCard(features: page.features),
          const SizedBox(height: 24),
          DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(9999)),
              boxShadow: AppTheme.shadowMd,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimary,
                  shape: const StadiumBorder(),
                ),
                onPressed: onGetStarted,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Get Started', style: AppTextStyles.labelLg),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surfaceContainerLow,
                foregroundColor: AppColors.onSurface,
                shape: const StadiumBorder(),
              ),
              onPressed: onLogin,
              child: Text(
                'I Already Have an Account',
                style: AppTextStyles.labelLg,
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onExploreDemo,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              // Underline drawn as a border to get the 4px offset.
              child: Container(
                padding: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.primaryFixedDim),
                  ),
                ),
                child: Text(
                  'Explore demo mode without an account',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTopBar extends StatelessWidget {
  const _StepTopBar({required this.onBack, required this.onSkip});

  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: AppColors.surfaceContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onBack,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.health_and_safety,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.appName.toUpperCase(),
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 0.025 * 12,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onSkip,
            borderRadius: BorderRadius.circular(9999),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Text(
                'Skip',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPageContent extends StatelessWidget {
  const _StepPageContent({
    required this.page,
    required this.index,
    required this.count,
    required this.onContinue,
    required this.onSignIn,
  });

  final OnboardingPage page;
  final int index;
  final int count;
  final VoidCallback onContinue;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    'Step ${index + 1} of $count',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
                _StepDots(count: count, current: index),
              ],
            ),
          ),
          const SizedBox(height: 16),
          VisitIllustrationCard(image: page.image),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title,
                  style: AppTextStyles.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  page.description,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.625,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              children: [
                for (final (i, feature) in page.features.indexed) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      height: 1,
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _StepFeatureRow(feature: feature),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(9999)),
              boxShadow: AppTheme.shadowMd,
            ),
            child: SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimary,
                  shape: const StadiumBorder(),
                ),
                onPressed: onContinue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Continue', style: AppTextStyles.labelLg),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: InkWell(
              onTap: onSignIn,
              borderRadius: BorderRadius.circular(9999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text.rich(
                  TextSpan(
                    text: 'Already have a profile? ',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    children: [
                      // Underline drawn as a border to get the 4px offset.
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AppColors.primary),
                            ),
                          ),
                          child: Text(
                            'Sign in',
                            style: AppTextStyles.labelMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: i == current ? 32 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.primaryContainer
                  : AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepFeatureRow extends StatelessWidget {
  const _StepFeatureRow({required this.feature});

  final OnboardingFeature feature;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: feature.iconBackground,
            shape: BoxShape.circle,
            boxShadow: AppTheme.shadowSm,
          ),
          child: Icon(feature.icon, color: feature.iconColor, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feature.description,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
