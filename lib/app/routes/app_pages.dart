import 'package:get/get.dart';

import '../../modules/home/bindings/home_binding.dart';
import '../../modules/add_medicine/bindings/add_medicine_binding.dart';
import '../../modules/add_medicine/views/add_medicine_view.dart';
import '../../modules/add_visit/bindings/add_visit_binding.dart';
import '../../modules/add_visit/views/add_visit_view.dart';
import '../../modules/home/views/home_view.dart';
import '../../modules/medicines/bindings/medicines_binding.dart';
import '../../modules/medicines/views/medicines_view.dart';
import '../../modules/login/bindings/login_binding.dart';
import '../../modules/login/views/login_view.dart';
import '../../modules/onboarding/bindings/onboarding_binding.dart';
import '../../modules/onboarding/views/onboarding_view.dart';
import '../../modules/profile_setup/bindings/profile_setup_binding.dart';
import '../../modules/profile_setup/views/profile_setup_view.dart';
import '../../modules/signup/bindings/signup_binding.dart';
import '../../modules/signup/views/signup_view.dart';
import '../../modules/verify_email/bindings/verify_email_binding.dart';
import '../../modules/verify_email/views/verify_email_view.dart';
import '../middlewares/auth_middleware.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final pages = <GetPage>[
    GetPage(
      name: AppRoutes.onboarding,
      page: () => const OnboardingView(),
      binding: OnboardingBinding(),
    ),
    GetPage(
      name: AppRoutes.login,
      page: () => const LoginView(),
      binding: LoginBinding(),
    ),
    GetPage(
      name: AppRoutes.signup,
      page: () => const SignupView(),
      binding: SignupBinding(),
    ),
    GetPage(
      name: AppRoutes.profileSetup,
      page: () => const ProfileSetupView(),
      binding: ProfileSetupBinding(),
      middlewares: [SignedInMiddleware()],
    ),
    GetPage(
      name: AppRoutes.verifyEmail,
      page: () => const VerifyEmailView(),
      binding: VerifyEmailBinding(),
      middlewares: [SignedInMiddleware()],
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    GetPage(
      name: AppRoutes.medicines,
      page: () => const MedicinesView(),
      binding: MedicinesBinding(),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    GetPage(
      name: AppRoutes.addVisit,
      page: () => const AddVisitView(),
      binding: AddVisitBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
    GetPage(
      name: AppRoutes.addMedicine,
      page: () => const AddMedicineView(),
      binding: AddMedicineBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
  ];
}
