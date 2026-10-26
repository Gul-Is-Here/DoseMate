import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/calendar_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/calendar/bindings/calendar_binding.dart';
import 'package:dosemate/modules/calendar/views/calendar_view.dart';
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
  late ProfileService profiles;
  late FakeCare careStore;
  late CareService care;
  late CalendarService calendar;
  late DateTime now;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  Future<void> start({Duration debounce = Duration.zero}) async {
    calendar = Get.put(CalendarService(care, debounce: debounce));
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    Get.testMode = true;
    now = fixedNow(); // Sat 24 Oct 2026, 2:00 PM
    final store = FakeProfiles()
      ..put(
        uid,
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Eleanor Vance',
        ),
      )
      ..put(
        uid,
        const UserProfile(
          id: 'p1',
          type: ProfileType.spouse,
          fullName: 'Arthur Vance',
        ),
      );
    profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    final auth = Get.put(AuthService(AuthRepository(NoAuth()), profiles));
    auth.user.value = FakeUser();
    careStore = FakeCare();
    seedCare(careStore);
    care = putCare(profiles, careStore, now: () => now);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  List<GetPage> pages() => [
    GetPage(
      name: AppRoutes.calendar,
      page: () => const RepaintBoundary(key: _shot, child: CalendarView()),
      binding: CalendarBinding(),
    ),
    for (final r in [
      AppRoutes.medicineDetails,
      AppRoutes.visitDetails,
      AppRoutes.addVisit,
      AppRoutes.home,
    ])
      GetPage(
        name: r,
        page: () => Scaffold(body: Text('page:$r')),
      ),
  ];

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 1600),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      GetMaterialApp(initialRoute: AppRoutes.calendar, getPages: pages()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Timeline times in display order.
  List<String> times(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+:\d\d [AP]M$').hasMatch(w.data ?? ''),
      ),
    ))
      t.data!,
  ];

  group('screen', () {
    setUp(() => start());

    testWidgets('today: doses in order, states, counts and progress', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Saturday, Oct 24 Ritual'), findsOneWidget);
      expect(find.text('2 doses remaining'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('Doses (3)'), findsOneWidget);
      expect(find.text('Appointments (0)'), findsOneWidget);
      expect(times(tester), ['8:00 AM', '9:00 AM', '8:00 PM']);
      expect(find.text('Overdue'), findsOneWidget); // 8 AM, unlogged
      expect(find.text('Mark Taken'), findsOneWidget);
      expect(find.text('Due tonight'), findsOneWidget);
      expect(find.text('Take Early'), findsOneWidget);
      expect(find.textContaining('Day 1 of 7'), findsNWidgets(2));
    });

    testWidgets('recurring doses respect start and end dates', (tester) async {
      await open(tester);
      // Friday: Amoxicillin hasn't started; Vitamin D has (Oct 1).
      await tester.tap(find.text('23'));
      await tester.pumpAndSettle();
      expect(find.text('Amoxicillin'), findsNothing);
      expect(find.text('Vitamin D3'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      // Nov 1: past Amoxicillin's 7-day course (ends Oct 30).
      calendar.select(DateTime(2026, 11, 1));
      await flush(tester);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsNothing);
      expect(find.text('Vitamin D3'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      // Oct 30: its last day.
      calendar.select(DateTime(2026, 10, 30));
      await flush(tester);
      expect(find.textContaining('Day 7 of 7'), findsNWidgets(2));
    });

    testWidgets('visits and doses order by time, visits first on ties', (
      tester,
    ) async {
      careStore.visitsOf(uid, 'self')
        ..['late'] = Visit(
          id: 'late',
          title: 'Physio',
          category: 'Specialist',
          startsAt: DateTime(2026, 10, 29, 20),
        )
        ..['tie'] = Visit(
          id: 'tie',
          title: 'Blood Test',
          category: 'Lab Test',
          startsAt: DateTime(2026, 10, 29, 8),
        );
      await open(tester);
      calendar.select(DateTime(2026, 10, 29));
      await flush(tester);
      expect(times(tester), [
        '8:00 AM', '8:00 AM', '9:00 AM', '3:30 PM', '8:00 PM', '8:00 PM', //
      ]);
      final titles = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (['Blood Test', 'Amoxicillin', 'Physio'].contains(t.data)) t.data,
      ];
      expect(titles, ['Blood Test', 'Amoxicillin', 'Physio', 'Amoxicillin']);
      expect(find.text('Appointments (3)'), findsOneWidget);
      // The filter shows only appointments.
      await tester.tap(find.text('Appointments (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Amoxicillin'), findsNothing);
      expect(find.text('Dentist Checkup & Cleaning'), findsOneWidget);
    });

    testWidgets('live: added, edited and cancelled visits; logged doses', (
      tester,
    ) async {
      await open(tester);
      final visit = Visit(
        id: 'v1',
        title: 'Eye Exam',
        category: 'Specialist',
        startsAt: DateTime(2026, 10, 24, 16),
        reminders: const ['1 hour before'],
        departureAlerts: true,
        notes: 'Bring glasses',
      );
      await care.saveVisit('self', visit, isNew: true);
      await flush(tester);
      expect(find.text('Eye Exam'), findsOneWidget);
      expect(find.text('In 2 hours'), findsOneWidget);
      expect(find.text('Today'), findsNWidgets(2)); // chip + time column
      expect(
        find.text('Alert 1 hour before (3:00 PM) & departure traffic alert'),
        findsOneWidget,
      );
      expect(find.text('“Bring glasses”'), findsOneWidget);
      await care.saveVisit(
        'self',
        Visit(
          id: 'v1',
          title: 'Eye Exam (moved)',
          category: 'Specialist',
          startsAt: DateTime(2026, 10, 24, 17),
        ),
        isNew: false,
      );
      await flush(tester);
      expect(find.text('Eye Exam (moved)'), findsOneWidget);
      expect(find.text('5:00 PM'), findsOneWidget);
      await care.cancelVisit('self', 'v1');
      await flush(tester);
      expect(find.textContaining('Eye Exam'), findsNothing);

      await tester.tap(find.text('Mark Taken'));
      await flush(tester);
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('repeated taps write a dose once', (tester) async {
      await open(tester);
      careStore.gate = Completer<void>();
      final before = careStore.writes;
      await tester.tap(find.text('Mark Taken'));
      await tester.pump();
      await tester.tap(find.text('Mark Taken'));
      await tester.pump();
      careStore.gate!.complete();
      await flush(tester);
      expect(careStore.writes - before, 1);
    });

    testWidgets('opens the details screens', (tester) async {
      await open(tester);
      await tester.tap(find.text('Vitamin D3'));
      await tester.pumpAndSettle();
      expect(find.text('page:${AppRoutes.medicineDetails}'), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      calendar.select(DateTime(2026, 10, 29));
      await flush(tester);
      await tester.tap(find.text('Dentist Checkup & Cleaning'));
      await tester.pumpAndSettle();
      expect(find.text('page:${AppRoutes.visitDetails}'), findsOneWidget);
    });

    testWidgets('switching profile clears at once, then shows theirs', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Amoxicillin'), findsNWidgets(2));
      unawaited(profiles.switchTo('p1'));
      await tester.pump();
      expect(find.text('Amoxicillin'), findsNothing);
      await flush(tester);
      expect(find.text('Lisinopril'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsNothing);
    });

    testWidgets('weeks in the 30-day window reuse its logs; older ones '
        'query their own', (tester) async {
      careStore.medicinesOf(uid, 'self')['vitd'] = Medicine(
        id: 'vitd',
        name: 'Vitamin D3',
        dosage: '1000 IU',
        frequency: Frequency.onceDaily,
        doseMinutes: const [9 * 60],
        startDate: DateTime(2026, 8, 1),
        courseDays: 365,
        quantity: 38,
      );
      careStore.logsOf(uid, 'self')['old'] = DoseLog(
        medicineId: 'vitd',
        day: DateTime(2026, 9, 2),
        minutes: 9 * 60,
        status: DoseStatus.taken,
        loggedAt: DateTime(2026, 9, 2, 9, 5),
      );
      await care.retry();
      await open(tester);
      var queries = careStore.rangeQueries;
      calendar.select(DateTime(2026, 10, 2)); // week of Sep 28: in window
      await flush(tester);
      expect(careStore.rangeQueries - queries, 1); // visits only
      queries = careStore.rangeQueries;
      calendar.select(DateTime(2026, 9, 2)); // week of Aug 31: older
      await flush(tester);
      expect(careStore.rangeQueries - queries, 2); // visits + logs
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Mark Taken'), findsNothing); // not today
    });

    testWidgets('load errors show retry; retry recovers', (tester) async {
      await open(tester);
      careStore.loadFailure = const CareFailure(
        'You don’t have access to this profile.',
      );
      await tester.tap(find.byTooltip('Next week'));
      await flush(tester);
      expect(find.text('Couldn’t load this week'), findsOneWidget);
      expect(
        find.text('You don’t have access to this profile.'),
        findsOneWidget,
      );
      careStore.loadFailure = null;
      await tester.tap(find.text('Retry'));
      await flush(tester);
      await tester.tap(find.text('29'));
      await tester.pumpAndSettle();
      expect(find.text('Dentist Checkup & Cleaning'), findsOneWidget);
    });

    testWidgets('empty day and Add Appointment', (tester) async {
      careStore.medicinesOf(uid, 'self').clear();
      await care.retry();
      await open(tester);
      expect(find.text('Nothing scheduled on this day'), findsOneWidget);
      await tester.tap(find.text('Add Appointment'));
      await tester.pumpAndSettle();
      expect(find.text('page:${AppRoutes.addVisit}'), findsOneWidget);
    });

    testWidgets('month picker and Today', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Select month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feb'));
      await flush(tester);
      expect(find.text('February 2027'), findsOneWidget);
      expect(calendar.selectedDay.value, DateTime(2027, 2, 24));
      await tester.tap(find.text('Today'));
      await flush(tester);
      expect(calendar.selectedDay.value, DateTime(2026, 10, 24));
    });

    testWidgets('small screen with large text: no overflow', (tester) async {
      await open(tester, size: const Size(320, 640), textScale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('service', () {
    test(
      'rapid week changes open one set of listeners, for the last week',
      () async {
        await start(debounce: const Duration(milliseconds: 50));
        final queries = careStore.rangeQueries;
        for (var i = 0; i < 5; i++) {
          calendar.shiftWeek(1);
        }
        expect(calendar.status, RangeStatus.loading);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(careStore.rangeQueries - queries, 1);
        expect(calendar.weekStart, DateTime(2026, 11, 23));
        expect(calendar.status, RangeStatus.ready);
      },
    );

    test('agendas are computed once per data change', () async {
      await start();
      calendar.selectedAgenda;
      calendar.selectedAgenda;
      calendar.agendaFor(DateTime(2026, 10, 20));
      final n = calendar.computations;
      calendar.selectedAgenda;
      expect(calendar.computations, n);
      await care.saveVisit(
        'self',
        Visit(
          id: 'x',
          title: 'X',
          category: 'Dentist',
          startsAt: DateTime(2026, 10, 24, 18),
        ),
        isNew: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calendar.selectedAgenda.visits, 1);
      expect(calendar.computations, n + 1);
    });

    test('old listeners are cancelled when the week changes', () async {
      await start();
      final listeners = careStore.listeners;
      calendar.shiftWeek(1);
      await Future<void>.delayed(Duration.zero);
      calendar.shiftWeek(-6); // > 30 days back: its own logs query too
      await Future<void>.delayed(Duration.zero);
      expect(careStore.listeners, listeners + 1);
      calendar.goToday();
      await Future<void>.delayed(Duration.zero);
      expect(careStore.listeners, listeners);
    });

    test('midnight: today and a "today" selection move on', () async {
      await start();
      now = DateTime(2026, 10, 25, 0, 0, 5);
      care.rollOver();
      await Future<void>.delayed(Duration.zero);
      expect(calendar.selectedDay.value, DateTime(2026, 10, 25));
      // Day 2 of Amoxicillin, from the new day's data.
      expect(calendar.selectedAgenda.doses, 3);
    });

    test('week boundaries: Monday start across years, months and DST', () {
      expect(
        CalendarService.weekStartOf(DateTime(2027, 1, 1)),
        DateTime(2026, 12, 28),
      );
      expect(
        CalendarService.weekStartOf(DateTime(2026, 11, 1, 23, 59)),
        DateTime(2026, 10, 26),
      );
      // Around DST changes (Mar 14 / Nov 7 2027 in the US): still midnight.
      for (final d in [DateTime(2027, 3, 16), DateTime(2027, 11, 9)]) {
        final start = CalendarService.weekStartOf(d);
        expect(start.hour, 0);
        expect(start.weekday, DateTime.monday);
      }
    });

    test('month change clamps the day, leap years included', () async {
      await start();
      calendar.select(DateTime(2028, 1, 31));
      calendar.selectMonth(2028, 2);
      expect(calendar.selectedDay.value, DateTime(2028, 2, 29));
      calendar.select(DateTime(2027, 1, 31));
      calendar.selectMonth(2027, 2);
      expect(calendar.selectedDay.value, DateTime(2027, 2, 28));
      calendar.selectMonth(2026, 10); // current month → today
      expect(calendar.selectedDay.value, DateTime(2026, 10, 24));
    });

    test('offline: pending writes still show', () async {
      await start();
      careStore.offline = true;
      final result = await care.saveVisit(
        'self',
        Visit(
          id: 'off',
          title: 'Offline visit',
          category: 'Dentist',
          startsAt: DateTime(2026, 10, 24, 18),
        ),
        isNew: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(result, WriteResult.pending);
      expect(calendar.selectedAgenda.visits, 1);
    });
  });

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['CALENDAR_SHOT'];
    if (out == null) return;
    now = DateTime(2026, 10, 24, 13, 30);
    careStore.medicinesOf(uid, 'self')['vitd'] = Medicine(
      id: 'vitd',
      name: 'Vitamin D',
      dosage: '1000 IU',
      notes: 'Taken with breakfast • 1 Softgel',
      frequency: Frequency.onceDaily,
      doseMinutes: const [9 * 60],
      startDate: DateTime(2026, 10, 24),
      courseDays: 90,
      quantity: 38,
    );
    careStore.medicinesOf(uid, 'self')['amox'] = Medicine(
      id: 'amox',
      name: 'Amoxicillin',
      dosage: '500mg',
      notes: 'Take with food',
      frequency: Frequency.onceDaily,
      doseMinutes: const [20 * 60],
      startDate: DateTime(2026, 10, 21),
      courseDays: 7,
      quantity: 10,
    );
    careStore.visitsOf(uid, 'self')['dentist'] = Visit(
      id: 'dentist',
      title: 'Dentist Checkup & Cleaning',
      category: 'Clinic Visit',
      startsAt: DateTime(2026, 10, 24, 15, 30),
      doctor: 'Dr. Robert Sterling',
      clinic: 'St. Jude Dental Clinic',
      address: 'Suite 400, 120 Medical Parkway',
      phone: '(555) 234-5678',
      notes: 'Bring updated medication list and new insurance card',
      reminders: const ['1 hour before'],
      departureAlerts: true,
    );
    await tester.runAsync(() async {
      await care.retry();
      await start();
    });
    debugDisableShadows = false;
    await open(tester, size: const Size(400, 1600));
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
