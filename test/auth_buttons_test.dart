import 'package:dosemate/core/theme/app_theme.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/login/view_model/login_view_model.dart';
import 'package:dosemate/modules/login/views/login_view.dart';
import 'package:dosemate/modules/signup/view_model/signup_view_model.dart';
import 'package:dosemate/modules/signup/views/signup_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_test.dart' show FakeAuth, FakePicker;
import 'support/fake_profiles.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    Get.testMode = true;
    Get.put(
      AuthService(
        AuthRepository(FakeAuth(), googlePicker: FakePicker()),
        ProfileService(FakeProfiles()),
      ),
    );
  });

  tearDown(Get.reset);

  // Wide enough for the square test font; layout is checked in screen tests.
  Future<void> show(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(theme: AppTheme.light, home: view));
    await tester.pump();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('sign in has no biometric option on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      Get.put(LoginViewModel());
      await show(tester, const LoginView());
      expect(find.textContaining('Face ID'), findsNothing);
      expect(find.textContaining('Fingerprint'), findsNothing);
      expect(find.byIcon(Icons.fingerprint), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('create account offers only Google on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    Get.put(SignupViewModel());
    await show(tester, const SignupView());
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('create account offers only Apple on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    Get.put(SignupViewModel());
    await show(tester, const SignupView());
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
