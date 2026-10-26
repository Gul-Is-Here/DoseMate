import 'package:get/get.dart';

import '../../modules/add_medicine/bindings/add_medicine_binding.dart';
import '../../modules/add_medicine/views/add_medicine_view.dart';
import '../../modules/add_visit/bindings/add_visit_binding.dart';
import '../../modules/add_visit/views/add_visit_view.dart';
import '../../modules/delete_account/bindings/delete_account_binding.dart';
import '../../modules/delete_account/views/delete_account_view.dart';
import '../../modules/family/bindings/family_binding.dart';
import '../../modules/family/views/family_view.dart';
import '../../modules/login/bindings/login_binding.dart';
import '../../modules/login/views/login_view.dart';
import '../../modules/notifications/bindings/notifications_binding.dart';
import '../../modules/notifications/views/notifications_view.dart';
import '../../modules/onboarding/bindings/onboarding_binding.dart';
import '../../modules/onboarding/views/onboarding_view.dart';
import '../../modules/profile_setup/bindings/profile_setup_binding.dart';
import '../../modules/profile_setup/views/profile_setup_view.dart';
import '../../modules/signup/bindings/signup_binding.dart';
import '../../modules/signup/views/signup_view.dart';
import '../../modules/verify_email/bindings/verify_email_binding.dart';
import '../../modules/verify_email/views/verify_email_view.dart';
import '../../modules/medicine_details/bindings/medicine_details_binding.dart';
import '../../modules/medicine_details/views/medicine_details_view.dart';
import '../../modules/visit_details/bindings/visit_details_binding.dart';
import '../../modules/visit_details/views/visit_details_view.dart';
import '../../modules/shell/bindings/shell_binding.dart';
import '../../modules/shell/views/main_shell_view.dart';
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
      middlewares: [VerifiedMiddleware()],
    ),
    GetPage(
      name: AppRoutes.verifyEmail,
      page: () => const VerifyEmailView(),
      binding: VerifyEmailBinding(),
      middlewares: [SignedInMiddleware()],
    ),
    // Main tabs share one shell; each route opens it on its own tab.
    GetPage(
      name: AppRoutes.home,
      page: () => const MainShellView(),
      binding: ShellBinding(initialTab: 0),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    // Main tabs share one shell; each route opens it on its own tab.
    GetPage(
      name: AppRoutes.medicines,
      page: () => const MainShellView(),
      binding: ShellBinding(initialTab: 1),
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
    GetPage(
      name: AppRoutes.medicineDetails,
      page: () => const MedicineDetailsView(),
      binding: MedicineDetailsBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
    // Main tabs share one shell; each route opens it on its own tab.
    GetPage(
      name: AppRoutes.calendar,
      page: () => const MainShellView(),
      binding: ShellBinding(initialTab: 2),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    // Main tabs share one shell; each route opens it on its own tab.
    GetPage(
      name: AppRoutes.history,
      page: () => const MainShellView(),
      binding: ShellBinding(initialTab: 3),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    // Main tabs share one shell; each route opens it on its own tab.
    GetPage(
      name: AppRoutes.settings,
      page: () => const MainShellView(),
      binding: ShellBinding(initialTab: 4),
      middlewares: [VerifiedMiddleware()],
      transition: Transition.noTransition,
    ),
    // Opened from Settings; back returns there.
    GetPage(
      name: AppRoutes.family,
      page: () => const FamilyView(),
      binding: FamilyBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
    GetPage(
      name: AppRoutes.visitDetails,
      page: () => const VisitDetailsView(),
      binding: VisitDetailsBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
    GetPage(
      name: AppRoutes.notifications,
      page: () => const NotificationsView(),
      binding: NotificationsBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
    GetPage(
      name: AppRoutes.deleteAccount,
      page: () => const DeleteAccountView(),
      binding: DeleteAccountBinding(),
      middlewares: [VerifiedMiddleware()],
    ),
  ];
}
