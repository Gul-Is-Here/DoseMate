import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/notifications/bindings/notifications_binding.dart';
import 'package:dosemate/modules/notifications/view_model/notifications_view_model.dart';
import 'package:dosemate/modules/notifications/views/notifications_view.dart';
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

void main() {
  const uid = 'uid-1';

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Get.testMode = true;
    final store = FakeProfiles()
      ..put(
        uid,
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Eleanor Vance',
        ),
      );
    final profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    Get.put(AuthService(AuthRepository(NoAuth()), profiles)).user.value =
        FakeUser();
    final care = FakeCare();
    seedCare(care);
    putCare(profiles, care, now: fixedNow);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  Future<void> openFromSettings(
    WidgetTester tester, {
    Size size = const Size(400, 2400),
    double textScale = 1,
    bool viaSettings = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Get.put(SettingsViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        home: viaSettings ? const SettingsView() : const Scaffold(),
        getPages: [
          GetPage(
            name: AppRoutes.notifications,
            page: () => const NotificationsView(),
            binding: NotificationsBinding(),
          ),
        ],
      ),
    );
    await tester.pump();
    if (viaSettings) {
      await tester.tap(find.byKey(const ValueKey('settings-notifications')));
    } else {
      Get.toNamed(AppRoutes.notifications);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Settings opens Notifications and back returns there', (
    tester,
  ) async {
    await openFromSettings(tester);
    expect(find.byType(NotificationsView), findsOneWidget);
    expect(find.text('Notifications & Alerts'), findsOneWidget);
    expect(find.text('Eleanor Vance (Primary)'), findsOneWidget);
    // From the profile's live data, not samples.
    expect(
      find.textContaining('MISSED SCHEDULED DOSE', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Amoxicillin supply low'), findsOneWidget);
    expect(find.text('Lisinopril 10mg'), findsNothing);
    expect(find.text('Caregiver Sync'), findsNothing);

    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsView), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('tabs filter and mark all read clears the dots', (tester) async {
    await openFromSettings(tester);
    // Today's overdue Amoxicillin, yesterday's unlogged Vitamin D3, and
    // Amoxicillin's low supply.
    expect(find.byKey(const ValueKey('unread')), findsNWidgets(3));
    await tester.tap(find.text('Refills'));
    await tester.pump();
    expect(find.text('Amoxicillin supply low'), findsOneWidget);
    expect(
      find.textContaining('MISSED SCHEDULED DOSE', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    expect(find.byKey(const ValueKey('unread')), findsNothing);
  });

  testWidgets('logging the dose removes its alert live', (tester) async {
    await openFromSettings(tester);
    await tester.tap(find.text('Take Now & Log'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('MISSED SCHEDULED DOSE', findRichText: true),
      findsNothing,
    );
    expect(find.text('Amoxicillin supply low'), findsOneWidget);
  });

  testWidgets('snooze hides the dose alert for now', (tester) async {
    await openFromSettings(tester);
    await tester.tap(find.text('Snooze 15m'));
    await tester.pump();
    expect(
      find.textContaining('MISSED SCHEDULED DOSE', findRichText: true),
      findsNothing,
    );
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(360, 780), 2.0),
  ]) {
    testWidgets('no overflow at ${size.width.toInt()}px, text x$scale', (
      tester,
    ) async {
      await openFromSettings(
        tester,
        size: size,
        textScale: scale,
        viaSettings: false,
      );
      await tester.scrollUntilVisible(
        find.text('Reminder Preferences'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Reminder Preferences'), findsOneWidget);
    });
  }

  test('saving read marks keeps other profiles\' marks', () {
    final vm = Get.put(NotificationsViewModel());
    vm.read.addAll(['dose:p1:lis_2026-10-24_420', 'dose:self:gone']);
    vm.markAllRead();
    final kept = vm.keptReadMarks();
    expect(kept, contains('dose:p1:lis_2026-10-24_420'));
    expect(kept, isNot(contains('dose:self:gone')));
    expect(kept, containsAll(vm.items.map((n) => n.id)));
  });

  testWidgets('mark all read turns off once nothing is unread', (tester) async {
    await openFromSettings(tester);
    TextButton markAll() => tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Mark all read'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(markAll().onPressed, isNotNull);
    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    expect(markAll().onPressed, isNull);
  });

  testWidgets('a category with nothing in it says so', (tester) async {
    await openFromSettings(tester);
    await tester.ensureVisible(find.text('Appointments'));
    await tester.tap(find.text('Appointments'));
    await tester.pump();
    expect(find.text('You\'re all caught up'), findsOneWidget);
    expect(find.text('Nothing in this category right now.'), findsOneWidget);
  });

  testWidgets('chips: 48dp targets, read as label and count', (tester) async {
    final semantics = tester.ensureSemantics();
    await openFromSettings(tester);
    final chip = find.byKey(const ValueKey('chip-Refills'));
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Refills, 1'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Today')).flagsCollection.isHeader,
      isTrue,
    );
    semantics.dispose();
  });
}
