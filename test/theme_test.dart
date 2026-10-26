import 'dart:math' as math;

import 'package:dosemate/core/theme/app_colors.dart';
import 'package:dosemate/core/theme/app_palette.dart';
import 'package:dosemate/core/theme/app_theme.dart';
import 'package:dosemate/core/theme/theme_controller.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/settings/view_model/settings_view_model.dart';
import 'package:dosemate/modules/settings/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    AppPalette.current = AppPalette.light;
    Get.reset();
  });

  group('palette', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      final name = p.isDark ? 'dark' : 'light';

      test('$name: text pairs reach 4.5:1', () {
        final pairs = {
          'text on background': (p.textPrimary, p.background),
          'text on card': (p.textPrimary, p.card),
          'text on input': (p.textPrimary, p.elevated),
          'text on selected': (p.textPrimary, p.selected),
          'secondary on background': (p.textSecondary, p.background),
          'secondary on card': (p.textSecondary, p.card),
          'secondary on input': (p.textSecondary, p.elevated),
          'primary on card': (p.primary, p.card),
          'primary on background': (p.primary, p.background),
          'on primary': (p.onPrimary, p.primary),
          'selected text': (p.onSelected, p.selected),
          'taken badge': (p.success, p.successContainer),
          'due badge': (p.attention, p.attentionContainer),
          'overdue badge': (p.error, p.errorContainer),
          'skipped badge': (p.neutral, p.neutralContainer),
          'taken on card': (p.success, p.card),
          'due on card': (p.attention, p.card),
          'error on card': (p.error, p.card),
          'on error': (p.onError, p.error),
          'snackbar': (p.onInverseSurface, p.inverseSurface),
        };
        for (final MapEntry(:key, value: (fg, bg)) in pairs.entries) {
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: key);
        }
      });

      test('$name: input edges and icons reach 3:1', () {
        for (final bg in [p.card, p.elevated, p.background]) {
          expect(_contrast(p.inputOutline, bg), greaterThanOrEqualTo(3));
        }
        expect(_contrast(p.primary, p.selected), greaterThanOrEqualTo(3));
      });

      test('$name: ThemeData carries the tokens', () {
        final theme = p.isDark ? AppTheme.dark : AppTheme.light;
        expect(theme.brightness, p.brightness);
        expect(theme.colorScheme.primary, p.primary);
        expect(theme.colorScheme.error, p.error);
        expect(theme.scaffoldBackgroundColor, p.background);
        expect(theme.extension<AppPalette>(), same(p));
      });
    }

    test('AppColors follow the current palette', () {
      AppPalette.current = AppPalette.dark;
      expect(AppColors.primary, AppPalette.dark.primary);
      expect(AppColors.surface, AppPalette.dark.background);
      expect(AppColors.surfaceContainerLowest, AppPalette.dark.card);
      AppPalette.current = AppPalette.light;
      expect(AppColors.onSurface, AppPalette.light.textPrimary);
    });
  });

  group('appearance', () {
    testWidgets('a choice is saved and restored', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final first = await tester.runAsync(() => ThemeController().init());
      await tester.runAsync(() => first!.setMode(ThemeMode.dark));
      expect(AppPalette.current, same(AppPalette.dark));
      AppPalette.current = AppPalette.light;
      final again = await tester.runAsync(() => ThemeController().init());
      expect(again!.mode.value, ThemeMode.dark);
      expect(AppPalette.current, same(AppPalette.dark));
    });

    testWidgets('System follows the phone’s setting as it changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = Get.put(
        (await tester.runAsync(() => ThemeController().init()))!,
      );
      expect(c.mode.value, ThemeMode.system);
      expect(AppPalette.current, same(AppPalette.light));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(AppPalette.current, same(AppPalette.dark));
      // A fixed choice ignores the system.
      await tester.runAsync(() => c.setMode(ThemeMode.light));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(AppPalette.current, same(AppPalette.light));
    });

    testWidgets('Settings switches the theme at once, keeping its state', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final profiles = ProfileService(
        FakeProfiles()..put(
          'uid-1',
          const UserProfile(
            id: UserProfile.selfId,
            type: ProfileType.self,
            fullName: 'Eleanor Vance',
          ),
        ),
      );
      await tester.runAsync(
        () => profiles.start('uid-1', selfName: 'Eleanor Vance'),
      );
      Get.put(AuthService(AuthRepository(NoAuth()), profiles)).user.value =
          FakeUser();
      putCare(profiles, FakeCare(), now: fixedNow);
      final appearance = Get.put(
        (await tester.runAsync(() => ThemeController().init()))!,
      );
      await tester.runAsync(() => appearance.setMode(ThemeMode.light));
      Get.put(SettingsViewModel());
      await tester.pumpWidget(
        Obx(
          () => GetMaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: appearance.mode.value,
            home: const SettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final settingsState = tester.state(find.byType(Scaffold).first);
      Color titleColor() => tester
          .widget<RichText>(
            find.descendant(
              of: find.text('Settings').first,
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color!;
      expect(titleColor(), AppPalette.light.textPrimary);
      expect(find.text('Light'), findsOneWidget); // the row's subtitle

      await tester.tap(find.byKey(const ValueKey('settings-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-dark')));
      await tester.pumpAndSettle();
      expect(appearance.mode.value, ThemeMode.dark);
      expect(AppPalette.current, same(AppPalette.dark));
      // Applied under the open sheet, without rebuilding the screen anew.
      expect(titleColor(), AppPalette.dark.textPrimary);
      expect(tester.state(find.byType(Scaffold).first), same(settingsState));
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString('appearance.mode'), 'dark');

      Get.back();
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);
      // Same layout in both themes: nothing overflows.
      expect(tester.takeException(), isNull);
    });
  });
}
