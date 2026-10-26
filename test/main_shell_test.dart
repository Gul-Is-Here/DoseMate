import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/calendar_service.dart';
import 'package:dosemate/data/services/history_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/calendar/view_model/calendar_view_model.dart';
import 'package:dosemate/modules/history/view_model/history_view_model.dart';
import 'package:dosemate/modules/home/view_model/home_view_model.dart';
import 'package:dosemate/modules/medicines/view_model/medicines_view_model.dart';
import 'package:dosemate/modules/shell/bindings/shell_binding.dart';
import 'package:dosemate/modules/shell/view_model/shell_view_model.dart';
import 'package:dosemate/modules/shell/views/main_shell_view.dart';
import 'package:dosemate/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

const _shot = ValueKey('shot');

void main() {
  const uid = 'uid-1';
  late FakeCare careStore;
  late CalendarService calendar;
  late HistoryService history;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  setUp(() async {
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
    final auth = Get.put(AuthService(AuthRepository(NoAuth()), profiles));
    auth.user.value = FakeUser();
    careStore = FakeCare();
    seedCare(careStore);
    // Enough history for several pages.
    final vit = careStore.medicinesOf(uid, 'self')['vitd']!;
    for (var d = 1; d <= 24; d++) {
      final l = DoseLog(
        medicineId: vit.id,
        day: DateTime(2026, 10, d),
        minutes: 9 * 60,
        status: DoseStatus.taken,
        loggedAt: DateTime(2026, 10, d, 9, 5),
        medicineName: 'Vitamin D3',
      );
      careStore.logsOf(uid, 'self')[l.id] = l;
    }
    final care = putCare(profiles, careStore, now: fixedNow);
    calendar = Get.put(CalendarService(care, debounce: Duration.zero));
    history = Get.put(HistoryService(care, pageSize: 5))
      ..range.value = HistoryRange.monthly;
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  Future<void> open(
    WidgetTester tester, {
    String route = AppRoutes.home,
    Size size = const Size(400, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: route,
        getPages: [
          for (final (name, tab) in [
            (AppRoutes.home, 0),
            (AppRoutes.medicines, 1),
            (AppRoutes.calendar, 2),
            (AppRoutes.history, 3),
            (AppRoutes.settings, 4),
          ])
            GetPage(
              name: name,
              page: () =>
                  const RepaintBoundary(key: _shot, child: MainShellView()),
              binding: ShellBinding(initialTab: tab),
              transition: Transition.noTransition,
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder navItem(String label) => find.descendant(
    of: find.byType(AppBottomNav),
    matching: find.bySemanticsLabel(label),
  );

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isSelected(WidgetTester tester, String label) =>
      tester.getSemantics(navItem(label)).flagsCollection.isSelected ==
      ui.Tristate.isTrue;

  testWidgets('every tab switches in place with one bar, highlighted', (
    tester,
  ) async {
    await open(tester);
    final routeBefore = Get.currentRoute;
    for (final (label, index) in [
      ('Medicines', 1),
      ('Calendar', 2),
      ('History', 3),
      ('Home', 0),
    ]) {
      await tapTab(tester, label);
      expect(Get.find<ShellViewModel>().index.value, index);
      expect(find.byType(AppBottomNav), findsOneWidget);
      expect(isSelected(tester, label), isTrue);
      expect(Get.currentRoute, routeBefore); // nothing was pushed
      expect(
        Navigator.of(tester.element(find.byType(AppBottomNav))).canPop(),
        isFalse,
      );
    }
  });

  testWidgets('tabs open lazily and keep one controller and listener', (
    tester,
  ) async {
    await open(tester);
    expect(Get.isRegistered<CalendarViewModel>(), isTrue); // lazy, unbuilt
    expect(careStore.historyHeads, 0); // History not opened yet
    await tapTab(tester, 'History');
    expect(careStore.historyHeads, 1);
    final historyVm = Get.find<HistoryViewModel>();
    await tapTab(tester, 'Calendar');
    final calendarVm = Get.find<CalendarViewModel>();
    final rangeQueries = careStore.rangeQueries;
    for (var i = 0; i < 3; i++) {
      await tapTab(tester, 'Home');
      await tapTab(tester, 'History');
      await tapTab(tester, 'Calendar');
      await tapTab(tester, 'Medicines');
    }
    expect(identical(Get.find<HistoryViewModel>(), historyVm), isTrue);
    expect(identical(Get.find<CalendarViewModel>(), calendarVm), isTrue);
    expect(Get.isRegistered<HomeViewModel>(), isTrue);
    expect(Get.isRegistered<MedicinesViewModel>(), isTrue);
    expect(careStore.historyHeads, 1); // no re-listen on return
    expect(careStore.rangeQueries, rangeQueries);
  });

  testWidgets('Calendar keeps its date and filter; History its filters, '
      'pages and scroll', (tester) async {
    await open(tester, size: const Size(400, 1300));
    await tapTab(tester, 'Calendar');
    await tester.tap(find.text('22'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Doses (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doses (1)'));
    await tester.pumpAndSettle();

    await tapTab(tester, 'History');
    await tester.tap(find.text('Status: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taken'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    final loaded = history.entries.length;
    expect(loaded, greaterThan(5));
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final offset = tester
        .state<ScrollableState>(scrollable.first)
        .position
        .pixels;
    expect(offset, greaterThan(0));
    final pages = careStore.historyPages;

    await tapTab(tester, 'Home');
    await tapTab(tester, 'Calendar');
    expect(calendar.selectedDay.value, DateTime(2026, 10, 22));
    expect(calendar.filter.value, CalendarFilter.doses);
    expect(find.text('Thursday, Oct 22 Ritual'), findsOneWidget);

    await tapTab(tester, 'History');
    // The filter row is scrolled out of view: the kept offset hides it.
    expect(history.statusFilter.value, DoseStatus.taken);
    expect(history.entries.length, loaded);
    expect(careStore.historyPages, pages); // no reload
    expect(
      tester.state<ScrollableState>(scrollable.first).position.pixels,
      offset,
    );
  });

  testWidgets('repeated and rapid taps never navigate or error', (
    tester,
  ) async {
    await open(tester);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Calendar'));
      await tester.tap(find.text('Calendar'));
      await tester.tap(find.text('History'));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(Get.find<ShellViewModel>().index.value, 3);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(Get.find<ShellViewModel>().index.value, 4);
    expect(isSelected(tester, 'Settings'), isTrue);
    expect(
      find.text('Your account, family profiles and alerts.'),
      findsOneWidget,
    );
  });

  testWidgets('tab routes open the shell on their tab', (tester) async {
    await open(tester, route: AppRoutes.history);
    expect(Get.find<ShellViewModel>().index.value, 3);
    expect(isSelected(tester, 'History'), isTrue);
    expect(find.text('Log History & Reports'), findsOneWidget);
  });

  testWidgets('back on a main tab leaves the shell as before', (tester) async {
    await open(tester);
    await tapTab(tester, 'Calendar');
    final navigator = Navigator.of(tester.element(find.byType(AppBottomNav)));
    // The shell is the only route, as each tab used to be, so system back
    // closes the app rather than walking back through tabs.
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('nav: small screen, 2x text, bottom inset: no overflow, '
      '48px targets above the inset', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(activeIndex: 1, onSelect: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in [
      'Home',
      'Medicines',
      'Calendar',
      'History',
      'Settings',
    ]) {
      final item = find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.bySemanticsLabel(RegExp('^$label')),
      );
      final rect = tester.getRect(item);
      expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      expect(rect.width, greaterThanOrEqualTo(48), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(640 - 34), reason: label);
    }
    expect(tester.getRect(find.byType(AppBottomNav)).bottom, 640);
  });

  testWidgets('shell on a small screen: no overflow on any tab', (
    tester,
  ) async {
    // Needs the real fonts: the default test font is far wider than Plus
    // Jakarta Sans and overflows existing Home/Medicines rows at 320px.
    if (Platform.environment['HOME_FONTS'] == null) return;
    await open(tester, size: const Size(320, 640));
    for (final label in [
      'Medicines',
      'Calendar',
      'History',
      'Settings',
      'Home',
    ]) {
      await tapTab(tester, label);
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['NAV_SHOT'];
    if (out == null) return;
    debugDisableShadows = false;
    await open(tester, size: const Size(400, 880));
    await tapTab(tester, 'Calendar');
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_shot),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  });
}
