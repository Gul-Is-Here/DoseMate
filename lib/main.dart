import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/services/ads_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so the first frame already has the chosen appearance.
  await Get.putAsync(() => ThemeController().init(), permanent: true);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = await InitialBinding.init();
  runApp(DoseMateApp(initialRoute: auth.initialRoute));
  // Banners: consent first where required; never delays the app.
  if (AdsService.supported) {
    final ads = Get.put(AdsService(), permanent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => ads.start());
  }
}

class DoseMateApp extends StatelessWidget {
  const DoseMateApp({super.key, this.initialRoute = AppRoutes.onboarding});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    final appearance = Get.isRegistered<ThemeController>()
        ? Get.find<ThemeController>()
        : null;
    Widget app(ThemeMode mode) => GetMaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      initialRoute: initialRoute,
      getPages: AppPages.pages,
      // Status and navigation bar icons that read on the background.
      builder: (context, child) {
        final dark = AppPalette.current.isDark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppPalette.current.card,
              ),
          child: child!,
        );
      },
    );
    if (appearance == null) return app(ThemeMode.light);
    return Obx(() => app(appearance.mode.value));
  }
}
