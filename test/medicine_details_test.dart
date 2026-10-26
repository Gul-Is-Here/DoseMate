import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/home/view_model/home_view_model.dart';
import 'package:dosemate/modules/home/views/home_view.dart';
import 'package:dosemate/modules/medicine_details/bindings/medicine_details_binding.dart';
import 'package:dosemate/modules/medicine_details/view_model/medicine_details_view_model.dart';
import 'package:dosemate/modules/medicine_details/views/medicine_details_view.dart';
import 'package:dosemate/modules/medicines/view_model/medicines_view_model.dart';
import 'package:dosemate/modules/medicines/views/medicines_view.dart';
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
  late DateTime now;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

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
    putCare(profiles, careStore, now: () => now);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  List<GetPage> pages() => [
    GetPage(
      name: AppRoutes.medicineDetails,
      page: () =>
          const RepaintBoundary(key: _shot, child: MedicineDetailsView()),
      binding: MedicineDetailsBinding(),
    ),
    GetPage(
      name: AppRoutes.addMedicine,
      page: () => const Scaffold(body: Text('page:edit')),
    ),
  ];

  /// Medicines → Medication Details, as a user would get there.
  Future<void> openFromMedicines(
    WidgetTester tester, {
    Size size = const Size(400, 1400),
    double inset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    addTearDown(tester.view.reset);
    Get.put(MedicinesViewModel());
    await tester.pumpWidget(
      GetMaterialApp(home: const MedicinesView(), getPages: pages()),
    );
    await tester.pump();
    await tester.tap(find.text('Amoxicillin'));
    await tester.pumpAndSettle();
  }

  /// Straight to one scheduled dose (as from Home's timeline).
  Future<void> openDose(
    WidgetTester tester,
    int minutes, {
    Size size = const Size(400, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('origin')),
        getPages: pages(),
      ),
    );
    Get.toNamed(
      AppRoutes.medicineDetails,
      arguments: MedicineDetailsArgs(
        medicineId: 'amox',
        profileId: 'self',
        day: DateTime(2026, 10, 24),
        minutes: minutes,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved medicine, not placeholders', (tester) async {
    await openFromMedicines(tester);
    expect(find.byType(MedicineDetailsView), findsOneWidget);
    // Today's next unlogged dose (8 AM, overdue at 2 PM).
    expect(find.text('DUE RIGHT NOW'), findsOneWidget);
    expect(
      find.text('8:00 AM (Morning Dose)', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('For Eleanor Vance'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('500mg - 1 capsule'), findsOneWidget);
    expect(find.text('“Take with dinner & full glass of water”'), findsOne);
    expect(find.text('3 doses left'), findsOneWidget);
    expect(find.text('Day 1 of 7'), findsOneWidget);
    expect(find.text('CareSync'), findsOneWidget);
  });

  testWidgets('missing optional fields are left out, not invented', (
    tester,
  ) async {
    careStore.medicinesOf(uid, 'self')['amox'] = Medicine(
      id: 'amox',
      name: 'Amoxicillin',
      frequency: Frequency.onceDaily,
      doseMinutes: const [20 * 60],
      startDate: DateTime(2026, 10, 24),
      courseDays: 7,
    );
    await Get.find<CareService>().retry();
    await openDose(tester, 20 * 60);
    expect(find.text('PATIENT DIRECTIONS'), findsNothing);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('0 doses left'), findsOneWidget);
  });

  testWidgets('Home timeline opens the tapped dose', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(HomeViewModel());
    await tester.pumpWidget(
      GetMaterialApp(home: const HomeView(), getPages: pages()),
    );
    await tester.pump();
    await tester.tap(find.text('Due tonight'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicineDetailsView), findsOneWidget);
    expect(
      find.text('8:00 PM (Evening Dose)', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('(Evening Dose)'), findsNothing); // part of a span
    expect(find.textContaining('Evening Dose'), findsOneWidget);
    expect(find.text('UPCOMING TODAY'), findsOneWidget);
  });

  testWidgets('Mark as Taken logs this occurrence with the note, once', (
    tester,
  ) async {
    await openDose(tester, 20 * 60);
    await tester.enterText(find.byType(TextField), 'took with soup');
    careStore.gate = Completer<void>();
    await tester.tap(find.text('Mark as Taken'));
    await tester.pump();
    // Repeated taps while saving do nothing.
    await tester.tap(find.text('Mark as Taken'), warnIfMissed: false);
    careStore.gate!.complete();
    careStore.gate = null;
    await tester.pump();
    await tester.pump();

    final log = careStore.logsOf(uid, 'self')['amox_2026-10-24_1200']!;
    expect(log.status, DoseStatus.taken);
    expect(log.note, 'took with soup');
    expect(careStore.writes, 1);
    expect(careStore.medicinesOf(uid, 'self')['amox']!.quantity, 2);
    // The 8 AM dose is untouched.
    expect(
      careStore.logsOf(uid, 'self').containsKey('amox_2026-10-24_480'),
      isFalse,
    );
    expect(find.text('2 doses left'), findsOneWidget);
    expect(find.textContaining('TAKEN AT'), findsOneWidget);
    expect(find.text('“took with soup”'), findsOneWidget);
    expect(find.text('Mark as Taken'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump();
    expect(
      careStore.logsOf(uid, 'self').containsKey('amox_2026-10-24_1200'),
      isFalse,
    );
    expect(find.text('3 doses left'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('Skip records skipped; supply is unchanged', (tester) async {
    await openDose(tester, 20 * 60);
    await tester.tap(find.text('Skip Dose'));
    await tester.pump();
    await tester.pump();
    expect(
      careStore.logsOf(uid, 'self')['amox_2026-10-24_1200']!.status,
      DoseStatus.skipped,
    );
    expect(careStore.medicinesOf(uid, 'self')['amox']!.quantity, 3);
    expect(find.text('SKIPPED'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('a failed save keeps the note and the buttons', (tester) async {
    await openDose(tester, 20 * 60);
    await tester.enterText(find.byType(TextField), 'late');
    careStore.failNext = const CareFailure(
      "You don't have permission to change this.",
      code: 'permission-denied',
    );
    await tester.tap(find.text('Mark as Taken'));
    await tester.pump();
    expect(find.text("Couldn't log dose"), findsOneWidget);
    expect(find.text('late'), findsOneWidget);
    expect(find.text('Mark as Taken'), findsOneWidget);
    expect(careStore.logsOf(uid, 'self'), hasLength(1)); // only Vitamin D3
    await flush(tester);
  });

  testWidgets('offline: shown as pending, not confirmed', (tester) async {
    await openDose(tester, 20 * 60);
    careStore.offline = true;
    await tester.tap(find.text('Mark as Taken'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('will sync when you'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('Snooze hides the dose for 15 minutes on this device', (
    tester,
  ) async {
    await openDose(tester, 20 * 60);
    await tester.tap(find.text('Snooze (15m)'));
    await tester.pump();
    expect(find.text('SNOOZED UNTIL 2:15 PM'), findsOneWidget);
    expect(careStore.writes, 0);
    await flush(tester);
  });

  testWidgets('edits made elsewhere show immediately', (tester) async {
    await openDose(tester, 20 * 60);
    final m = careStore.medicinesOf(uid, 'self')['amox']!;
    await careStore.saveMedicine(
      uid,
      'self',
      m.copyWith(quantity: 18),
      isNew: false,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('18 doses left'), findsOneWidget);
  });

  testWidgets('deleted: shows unavailable with a way back', (tester) async {
    await openDose(tester, 20 * 60);
    await careStore.deleteMedicine(uid, 'self', 'amox');
    await tester.pump();
    await tester.pump();
    expect(find.text('This medicine is no longer available'), findsOneWidget);
    await tester.tap(find.text('Go Back'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('switching profile closes the screen', (tester) async {
    await openDose(tester, 20 * 60);
    await profiles.switchTo('p1');
    await tester.pumpAndSettle();
    expect(find.byType(MedicineDetailsView), findsNothing);
    expect(find.text('Amoxicillin'), findsNothing);
    expect(find.text('origin'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('load errors show a retry', (tester) async {
    careStore.loadFailure = const CareFailure(
      'You do not have permission.',
      code: 'permission-denied',
    );
    await Get.find<CareService>().retry();
    await openDose(tester, 20 * 60);
    expect(find.text('You do not have permission.'), findsOneWidget);
    careStore.loadFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Amoxicillin'), findsOneWidget);
  });

  testWidgets('custom time: log a missed earlier dose, or edit schedule', (
    tester,
  ) async {
    await openDose(tester, 20 * 60, size: const Size(400, 1600));
    await tester.tap(find.text('Log custom time or edit schedule'));
    await tester.pumpAndSettle();
    // Only the dose that is already due (8 AM) is offered.
    expect(find.text('Today • 8:00 AM'), findsOneWidget);
    expect(find.text('Today • 8:00 PM'), findsNothing);
    await tester.tap(find.text('Today • 8:00 AM'));
    await tester.pumpAndSettle();
    expect(
      careStore.logsOf(uid, 'self')['amox_2026-10-24_480']!.status,
      DoseStatus.taken,
    );
    await flush(tester);

    await tester.tap(find.text('Log custom time or edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit schedule'));
    await tester.pumpAndSettle();
    expect(find.text('page:edit'), findsOneWidget);
  });

  testWidgets('close (minimize) returns to the previous screen', (
    tester,
  ) async {
    await openDose(tester, 20 * 60);
    await tester.tap(find.byTooltip('Minimize Reminder'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
  });

  final realFonts = Platform.environment.containsKey('HOME_FONTS');
  for (final width in [if (realFonts) 320.0, 360.0, 400.0, 600.0]) {
    testWidgets('no overflow at ${width.toInt()}px wide', (tester) async {
      await openDose(tester, 20 * 60, size: Size(width, 1800));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard open: no overflow and the note stays visible', (
    tester,
  ) async {
    await openFromMedicines(tester, size: const Size(360, 740), inset: 300);
    await tester.showKeyboard(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(TextField)).bottom, lessThan(740 - 300));
  });

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['DETAILS_SHOT'];
    if (out == null) return;
    now = DateTime(2026, 10, 24, 19, 55);
    final m = careStore.medicinesOf(uid, 'self')['amox']!;
    careStore.medicinesOf(uid, 'self')['amox'] = Medicine(
      id: m.id,
      name: 'Amoxicillin 500mg',
      dosage: '1 Capsule • Oral',
      notes: 'Take with dinner and a full glass of water',
      frequency: m.frequency,
      doseMinutes: m.doseMinutes,
      startDate: DateTime(2026, 10, 19),
      courseDays: 10,
      quantity: 18,
    );
    await Get.find<CareService>().retry();
    debugDisableShadows = false;
    await openDose(tester, 20 * 60, size: const Size(400, 1220));
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
