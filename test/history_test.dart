import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/core/utils/history_export.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/history_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/history/bindings/history_binding.dart';
import 'package:dosemate/modules/history/views/history_view.dart';
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
  late HistoryService history;
  late DateTime now;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  DoseLog log(
    String medicineId,
    DateTime day,
    int minutes, {
    DoseStatus status = DoseStatus.taken,
    int lateBy = 5,
    String? name,
    String? dosage,
    String? note,
  }) => DoseLog(
    medicineId: medicineId,
    day: day,
    minutes: minutes,
    status: status,
    loggedAt: DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: minutes + lateBy)),
    medicineName: name,
    dosage: dosage,
    note: note,
  );

  void put(DoseLog l, {String pid = 'self'}) =>
      careStore.logsOf(uid, pid)[l.id] = l;

  /// Vitamin D3 taken at 9 AM on each of the [days] days up to today.
  void vitaminDays(int days) {
    for (var i = 0; i < days; i++) {
      put(log('vitd', DateTime(2026, 10, 24 - i), 9 * 60, name: 'Vitamin D3'));
    }
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
    careStore.logsOf(uid, 'self').clear();
    care = putCare(profiles, careStore, now: () => now);
    history = Get.put(HistoryService(care, pageSize: 5));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  Future<void> reload() async {
    await care.retry();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> activate() async {
    history.activate();
    await Future<void>.delayed(Duration.zero);
  }

  List<String> ids() => [for (final l in history.entries) l.id];

  group('service', () {
    test('newest first, ties ordered by id, one page at a time', () async {
      vitaminDays(7);
      put(log('amox', DateTime(2026, 10, 24), 9 * 60, name: 'Amoxicillin'));
      await reload();
      await activate();
      expect(history.status.value, HistoryStatus.ready);
      expect(ids(), [
        'vitd_2026-10-24_540', 'amox_2026-10-24_540', // same day and minute
        'vitd_2026-10-23_540', 'vitd_2026-10-22_540', 'vitd_2026-10-21_540',
      ]);
      await history.loadMore();
      expect(history.entries.length, 8);
      expect(history.pageStatus.value, PageStatus.end);
      expect(ids().toSet().length, 8); // no duplicates
      expect(careStore.historyPages, 1);
      await history.loadMore(); // at the end: no read
      expect(careStore.historyPages, 1);
    });

    test('repeated load-more triggers fetch once', () async {
      vitaminDays(7);
      await reload();
      await activate();
      careStore.pageGate = Completer<void>();
      final a = history.loadMore(), b = history.loadMore();
      careStore.pageGate!.complete();
      await Future.wait([a, b]);
      expect(careStore.historyPages, 1);
      expect(history.entries.length, 7);
    });

    test('live: new logs arrive at the top, deletions leave, pushed-out '
        'logs stay', () async {
      vitaminDays(7);
      await reload();
      await activate();
      await history.loadMore(); // all 7 loaded
      // A new log (today, later minute) pushes the 5th head entry out.
      await care.logDose(
        DoseOccurrence(
          care.medicineById('amox')!,
          DateTime(2026, 10, 24),
          20 * 60,
        ),
        DoseStatus.skipped,
      );
      await Future<void>.delayed(Duration.zero);
      expect(history.entries.first.id, 'amox_2026-10-24_1200');
      expect(history.entries.first.medicineName, 'Amoxicillin');
      expect(history.entries.length, 8);
      expect(ids().toSet().length, 8);
      // Undo deletes it from Firestore and from the list.
      await care.undoDose(care.logs['amox_2026-10-24_1200']!);
      await Future<void>.delayed(Duration.zero);
      expect(history.entries.length, 7);
      expect(ids(), isNot(contains('amox_2026-10-24_1200')));
    });

    test('a failed page keeps loaded entries and can be retried', () async {
      vitaminDays(7);
      await reload();
      await activate();
      careStore.failNextPage = const CareFailure('No connection.');
      await history.loadMore();
      expect(history.pageStatus.value, PageStatus.error);
      expect(history.pageError.value, 'No connection.');
      expect(history.entries.length, 5);
      await history.loadMore();
      expect(history.entries.length, 7);
      expect(history.pageStatus.value, PageStatus.end);
    });

    test(
      'offline: a short page from the cache is not treated as the end',
      () async {
        vitaminDays(7);
        await reload();
        await activate();
        careStore.pagesFromCache = true;
        await history.loadMore();
        expect(history.entries.length, 7);
        expect(history.pageStatus.value, PageStatus.idle);
        careStore.pagesFromCache = false;
        await history.loadMore();
        expect(history.pageStatus.value, PageStatus.end);
      },
    );

    test('filters reset paging; an outdated page is ignored', () async {
      vitaminDays(7);
      put(
        log(
          'amox',
          DateTime(2026, 10, 22),
          20 * 60,
          status: DoseStatus.skipped,
          name: 'Amoxicillin',
        ),
      );
      await reload();
      await activate();
      careStore.pageGate = Completer<void>();
      final pending = history.loadMore();
      history.statusFilter.value = DoseStatus.skipped;
      careStore.pageGate!.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(ids(), ['amox_2026-10-22_1200']);
      expect(history.pageStatus.value, PageStatus.end);

      history.statusFilter.value = null;
      history.medicineId.value = 'vitd';
      await Future<void>.delayed(Duration.zero);
      expect(history.entries.every((l) => l.medicineId == 'vitd'), isTrue);

      history.medicineId.value = null;
      history.newestFirst.value = false;
      await Future<void>.delayed(Duration.zero);
      expect(history.entries.first.id, 'vitd_2026-10-18_540');
    });

    test('date ranges: today only, last 7 days, last 30 days', () async {
      vitaminDays(31); // Sep 24 … Oct 24
      await reload();
      history.range.value = HistoryRange.daily;
      await activate();
      expect(ids(), ['vitd_2026-10-24_540']);
      expect(history.pageStatus.value, PageStatus.end);
      history.range.value = HistoryRange.weekly;
      await Future<void>.delayed(Duration.zero);
      while (history.pageStatus.value != PageStatus.end) {
        await history.loadMore();
      }
      expect(history.entries.length, 7);
      expect(history.entries.last.day, DateTime(2026, 10, 18));
      history.range.value = HistoryRange.monthly;
      await Future<void>.delayed(Duration.zero);
      while (history.pageStatus.value != PageStatus.end) {
        await history.loadMore();
      }
      expect(history.entries.length, 30);
      expect(history.entries.last.day, DateTime(2026, 9, 25));
    });

    test('midnight moves the range', () async {
      vitaminDays(7);
      await reload();
      history.range.value = HistoryRange.daily;
      await activate();
      expect(history.entries.length, 1);
      now = DateTime(2026, 10, 25, 0, 0, 5);
      care.rollOver();
      await Future<void>.delayed(Duration.zero);
      expect(history.entries, isEmpty);
      expect(history.bounds.$1, DateTime(2026, 10, 25));
    });

    test('switching profile clears at once and resets its filter', () async {
      vitaminDays(3);
      put(
        log('lis', DateTime(2026, 10, 24), 7 * 60, name: 'Lisinopril'),
        pid: 'p1',
      );
      await reload();
      await activate();
      history.medicineId.value = 'vitd';
      await Future<void>.delayed(Duration.zero);
      unawaited(profiles.switchTo('p1'));
      expect(history.entries, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(history.medicineId.value, isNull);
      expect(ids(), ['lis_2026-10-24_420']);
    });

    test('load errors surface and retry recovers', () async {
      vitaminDays(2);
      await reload();
      careStore.loadFailure = const CareFailure('Permission denied.');
      await activate();
      expect(history.status.value, HistoryStatus.error);
      expect(history.error.value, 'Permission denied.');
      careStore.loadFailure = null;
      await history.retry();
      await Future<void>.delayed(Duration.zero);
      expect(history.status.value, HistoryStatus.ready);
      expect(history.entries.length, 2);
    });

    test('summary counts recorded doses and unmarked past ones', () async {
      put(log('vitd', DateTime(2026, 10, 24), 9 * 60));
      put(
        log('amox', DateTime(2026, 10, 24), 8 * 60, status: DoseStatus.skipped),
      );
      await reload();
      history.range.value = HistoryRange.daily;
      final s = history.summary;
      expect((s.taken, s.skipped, s.unmarked), (1, 1, 0)); // 8 PM not due yet
      now = DateTime(2026, 10, 24, 21);
      expect(history.summary.unmarked, 1);
    });

    test('CSV quotes cells and neutralises formulas', () {
      final csv = String.fromCharCodes(
        historyCsv([
          ExportRow(
            day: DateTime(2026, 10, 22),
            scheduledMinutes: 20 * 60,
            medicine: '=HYPERLINK("x")',
            dosage: '500mg, 1 capsule',
            status: 'Skipped',
            loggedAt: DateTime(2026, 10, 22, 20, 5),
            note: 'Said "later"',
          ),
        ]),
      );
      final line = csv.split('\r\n')[1];
      expect(
        line,
        '"2026-10-22","8:00 PM","\'=HYPERLINK(""x"")",'
        '"500mg, 1 capsule","Skipped","8:05 PM","Said ""later"""',
      );
    });
  });

  group('screen', () {
    List<GetPage> pages() => [
      GetPage(
        name: AppRoutes.history,
        page: () => const RepaintBoundary(key: _shot, child: HistoryView()),
        binding: HistoryBinding(),
      ),
      GetPage(name: AppRoutes.home, page: () => const Text('page:home')),
    ];

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(400, 2000),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        GetMaterialApp(initialRoute: AppRoutes.history, getPages: pages()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('rows, day headings, snapshots and deleted medicines', (
      tester,
    ) async {
      await tester.runAsync(() async {
        put(
          log(
            'vitd',
            DateTime(2026, 10, 24),
            9 * 60,
            lateBy: 8,
            name: 'Vitamin D3',
            dosage: '1000 IU • Softgel',
          ),
        );
        // Renamed since: the log keeps the old name.
        put(
          log(
            'amox',
            DateTime(2026, 10, 23),
            20 * 60,
            lateBy: 15,
            name: 'Amoxicillin (old name)',
            dosage: '500mg • Capsule',
          ),
        );
        put(
          log(
            'amox',
            DateTime(2026, 10, 22),
            20 * 60,
            status: DoseStatus.skipped,
            note: 'Tummy sensitivity after lunch',
          ),
        );
        // Medicine deleted, and an older log without a snapshot.
        put(log('gone', DateTime(2026, 10, 21), 8 * 60));
        await reload();
      });
      await open(tester);
      expect(find.text('Log History & Reports'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Thursday, Oct 22'), findsOneWidget);
      expect(find.text('Marked Taken at 9:08 AM'), findsOneWidget);
      expect(find.text('Sched 9:00 AM'), findsOneWidget);
      expect(find.text('Amoxicillin (old name)'), findsOneWidget);
      expect(find.text('Marked Taken at 8:15 PM'), findsOneWidget);
      // No snapshot: falls back to the current medicine.
      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('Skipped at 8:05 PM'), findsOneWidget);
      expect(
        find.text('Note: “Tummy sensitivity after lunch”'),
        findsOneWidget,
      );
      expect(find.text('Medicine no longer available'), findsOneWidget);
      expect(
        find.text('This Week: 4 scheduled doses recorded'),
        findsOneWidget,
      );
      expect(find.text('3 Marked Taken (75%)'), findsOneWidget);
      expect(find.text('1 Skipped'), findsOneWidget);
      expect(find.text('Oct 18 – Oct 24'), findsOneWidget);
    });

    testWidgets('filters via sheets, empty and no-match states', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('No history yet'), findsOneWidget);
      await tester.runAsync(() async {
        await care.logDose(
          DoseOccurrence(
            care.medicineById('vitd')!,
            DateTime(2026, 10, 24),
            540,
          ),
          DoseStatus.taken,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Vitamin D3'), findsOneWidget);
      await tester.tap(find.text('Status: All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Skipped'), findsOneWidget);
      expect(find.text('No matching records'), findsOneWidget);
      await tester.tap(find.text('All Medicines'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vitamin D3').last);
      await tester.pumpAndSettle();
      expect(history.medicineId.value, 'vitd');
    });

    testWidgets('export asks permission first; Cancel does nothing', (
      tester,
    ) async {
      await open(tester);
      await tester.ensureVisible(find.text('Export CSV'));
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Report Export'), findsOneWidget);
      expect(find.textContaining('Eleanor Vance'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Report Export'), findsNothing);
    });

    testWidgets('small screen with large text: no overflow', (tester) async {
      await tester.runAsync(() async {
        put(
          log(
            'amox',
            DateTime(2026, 10, 22),
            20 * 60,
            status: DoseStatus.skipped,
            note: 'A long note to wrap',
          ),
        );
        await reload();
      });
      await open(tester, size: const Size(320, 640), textScale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reference-size screenshot', (tester) async {
      final out = Platform.environment['HISTORY_SHOT'];
      if (out == null) return;
      await tester.runAsync(() async {
        put(
          log(
            'vitd',
            DateTime(2026, 10, 24),
            9 * 60,
            lateBy: 8,
            name: 'Vitamin D3',
            dosage: '1000 IU • Softgel',
          ),
        );
        put(
          log(
            'amox',
            DateTime(2026, 10, 23),
            20 * 60,
            lateBy: 15,
            name: 'Amoxicillin',
            dosage: '500mg • Capsule',
          ),
        );
        put(
          log(
            'vitd',
            DateTime(2026, 10, 23),
            9 * 60,
            lateBy: 2,
            name: 'Vitamin D3',
            dosage: '1000 IU • Softgel',
          ),
        );
        put(
          log(
            'amox',
            DateTime(2026, 10, 22),
            20 * 60,
            status: DoseStatus.skipped,
            name: 'Amoxicillin',
            dosage: '500mg • Capsule',
            note: 'Tummy sensitivity after lunch',
          ),
        );
        await reload();
      });
      debugDisableShadows = false;
      await open(tester, size: const Size(400, 1900));
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
  });
}
