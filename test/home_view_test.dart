import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/home/view_model/home_view_model.dart';
import 'package:dosemate/modules/home/views/home_view.dart';
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
  late FakeProfiles store;
  late ProfileService profiles;
  late FakeCare careStore;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  setUp(() async {
    Get.testMode = true;
    store = FakeProfiles()
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
    putCare(profiles, careStore, now: fixedNow);
    Get.put(HomeViewModel());
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: const RepaintBoundary(key: _shot, child: HomeView()),
      ),
    );
    await tester.pump();
  }

  testWidgets('header shows the active profile and follows a switch', (
    tester,
  ) async {
    await pump(tester, const Size(400, 900));
    expect(find.text('Eleanor Vance'), findsOneWidget);
    expect(find.text('Eleanor (Self)'), findsOneWidget);
    expect(find.textContaining(', Eleanor'), findsOneWidget);

    await profiles.switchTo('p1');
    await tester.pump();
    expect(find.text('Arthur Vance'), findsOneWidget);
    expect(find.text('Arthur (Spouse)'), findsOneWidget);
    expect(find.textContaining(', Arthur'), findsOneWidget);
  });

  testWidgets('progress, next dose, timeline, refill and visit are real', (
    tester,
  ) async {
    await pump(tester, const Size(400, 2400));
    expect(find.text('1 of 3 doses taken today'), findsOneWidget);
    expect(find.text('Vitamin D3 logged at 9:08 AM'), findsOneWidget);
    expect(find.text('Next Dose: 8:00 AM Today'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets);
    expect(find.text('9:08 AM ✓'), findsOneWidget);
    expect(find.text('Due tonight'), findsOneWidget);
    expect(find.text('3 Events'), findsOneWidget);
    expect(find.text('Saturday, Oct 24 • Scheduled routines'), findsOneWidget);
    expect(find.text('3 doses left'), findsOneWidget);
    expect(find.text('Dentist Checkup & Cleaning'), findsOneWidget);
    expect(find.text('Thursday • 3:30 PM'), findsOneWidget);
    expect(find.text('In 5 days'), findsOneWidget);
    expect(find.text('DEMO'), findsNothing);
  });

  testWidgets('skip records that occurrence; undo removes it', (tester) async {
    await pump(tester, const Size(400, 2400));
    await tester.tap(find.text('Skip Dose'));
    await tester.pump();
    await tester.pump();
    expect(
      careStore.logsOf(uid, 'self')['amox_2026-10-24_480']?.status,
      DoseStatus.skipped,
    );
    // Only the 8 AM dose: the 8 PM one is now next.
    expect(find.text('Amoxicillin (8:00 AM) marked as skipped.'), findsOne);
    expect(find.text('Next Dose: 8:00 PM Tonight'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump();
    expect(careStore.logsOf(uid, 'self'), hasLength(1));
    expect(find.text('Next Dose: 8:00 AM Today'), findsOneWidget);
  });

  testWidgets('taking a dose lowers the supply once', (tester) async {
    await pump(tester, const Size(400, 2400));
    await tester.tap(find.text('✓ Mark as Taken'));
    await tester.pump();
    await tester.pump();
    expect(careStore.medicinesOf(uid, 'self')['amox']!.quantity, 2);
    expect(find.text('2 of 3 doses taken today'), findsOneWidget);
  });

  testWidgets('switching profile shows only that profile’s data', (
    tester,
  ) async {
    await pump(tester, const Size(400, 2400));
    await profiles.switchTo('p1');
    await tester.pump();
    await tester.pump();
    expect(find.text('Amoxicillin'), findsNothing);
    expect(find.text('Dentist Checkup & Cleaning'), findsNothing);
    expect(find.text('Lisinopril'), findsWidgets);
    expect(find.text('0 of 1 dose taken today'), findsOneWidget);
  });

  testWidgets('empty profile shows the empty state with working actions', (
    tester,
  ) async {
    careStore.medicines.clear();
    careStore.visits.clear();
    careStore.logs.clear();
    await Get.find<CareService>().retry();
    await pump(tester, const Size(400, 1600));
    await tester.pump();
    expect(find.text('No schedules created yet'), findsOneWidget);
    expect(find.text('Add First Medicine'), findsOneWidget);
    expect(find.text('Schedule a Doctor Visit'), findsOneWidget);
  });

  testWidgets('load errors show a retry that recovers', (tester) async {
    careStore.loadFailure = const CareFailure(
      'You do not have permission.',
      code: 'permission-denied',
    );
    await Get.find<CareService>().retry();
    await pump(tester, const Size(400, 1600));
    await tester.pump();
    expect(find.text('You do not have permission.'), findsOneWidget);
    careStore.loadFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 of 3 doses taken today'), findsOneWidget);
  });

  // The default test font draws every glyph a full em wide, so the smallest
  // phone width is only meaningful with the real fonts loaded.
  final realFonts = Platform.environment.containsKey('HOME_FONTS');
  for (final width in [if (realFonts) 320.0, 360.0, 400.0, 600.0]) {
    testWidgets('no overflow at ${width.toInt()}px wide', (tester) async {
      await pump(tester, Size(width, 2400));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['HOME_SHOT'];
    if (out == null) return;
    // Tests draw shadows unblurred by default; show them as on device.
    debugDisableShadows = false;
    await pump(tester, const Size(400, 1600));
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
