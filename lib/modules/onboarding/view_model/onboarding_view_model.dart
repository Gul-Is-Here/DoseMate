import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/onboarding_page.dart';

class OnboardingViewModel extends GetxController {
  final pageController = PageController();
  final currentIndex = 0.obs;

  // A getter: the colours follow the current theme.
  List<OnboardingPage> get pages => <OnboardingPage>[
    OnboardingPage(
      image: 'assets/onboarding/onboarding1.png',
      badge: 'Peace of Mind',
      title: 'Never Miss a Scheduled Dose',
      description:
          'Easily record your prescribed medicines, set custom reminder times, '
          'and log when taken with a single gentle tap.',
      features: [
        OnboardingFeature(
          icon: Icons.notifications_active,
          iconBackground: AppColors.primaryFixed,
          iconColor: AppColors.onPrimaryFixed,
          title: 'Reliable Device Alerts',
          description:
              'Works smoothly with phone notification settings so critical '
              'routines stay on track.',
        ),
        OnboardingFeature(
          icon: Icons.verified_user,
          iconBackground: AppColors.secondaryFixed,
          iconColor: AppColors.onSecondaryFixed,
          title: 'No Medical Guesswork',
          description:
              'DoseMate records user-entered schedules and never diagnoses or '
              'alters your care plan.',
        ),
      ],
    ),
    OnboardingPage(
      image: 'assets/onboarding/onboarding2.png',
      title: 'Organize Doctor & Clinic Visits',
      description:
          'Keep dental cleanings, checkups, and doctor consultations alongside '
          'your daily medication schedule.',
      features: [
        OnboardingFeature(
          icon: Icons.medical_information,
          iconBackground: AppColors.surfaceContainerLowest,
          iconColor: AppColors.primary,
          title: 'Visit Preparation Notes',
          description:
              'Save clinic locations, dial your doctor directly, and store '
              'appointment notes.',
        ),
        OnboardingFeature(
          icon: Icons.notifications_active,
          iconBackground: AppColors.surfaceContainerLowest,
          iconColor: AppColors.secondary,
          title: 'Advance Departure Alerts',
          description:
              'Get scheduled reminders before your visit so you have ample '
              'time to prepare.',
        ),
      ],
    ),
    OnboardingPage(
      // TODO: replace with the "Care Circle" illustration from the design.
      image: 'assets/onboarding/onboarding3.png',
      title: 'Peace of Mind for Families & Caregivers',
      description:
          'Coordinate care with loved ones while keeping complete control '
          'over your private health data.',
      features: [
        OnboardingFeature(
          icon: Icons.shield_outlined,
          iconBackground: AppColors.primaryFixed,
          iconColor: AppColors.onPrimaryFixed,
          title: 'Granular Privacy Safeguards',
          description:
              'Choose exactly what caregivers can view without exposing '
              'sensitive diagnoses or personal notes.',
        ),
        OnboardingFeature(
          icon: Icons.lock_open,
          iconBackground: AppColors.secondaryFixed,
          iconColor: AppColors.onSecondaryFixed,
          title: 'No Gated Sign-up',
          description:
              'Explore the complete app in demo mode anytime before creating '
              'your free profile.',
        ),
      ],
    ),
  ];

  bool get isLastPage => currentIndex.value == pages.length - 1;

  void onPageChanged(int index) => currentIndex.value = index;

  void next() {
    if (isLastPage) {
      finish();
      return;
    }
    pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void previous() => pageController.previousPage(
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOut,
  );

  void skip() => Get.offAllNamed(AppRoutes.login);

  void login() => Get.toNamed(AppRoutes.login);

  void getStarted() => Get.toNamed(AppRoutes.signup);

  void exploreDemo() => finish();

  void finish() => Get.offAllNamed(AppRoutes.home);

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
