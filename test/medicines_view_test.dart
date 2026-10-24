import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
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
    Get.put(MedicinesViewModel());
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: const RepaintBoundary(key: _shot, child: MedicinesView()),
      ),
    );
    await tester.pump();
  }

  testWidgets('header and banner follow the active profile', (tester) async {
    await pump(tester, const Size(400, 900));
    expect(find.text('Eleanor (Active)'), findsOneWidget);
    await profiles.switchTo('p1');
    await tester.pump();
    expect(find.text('Arthur (Active)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Arthur’s linked'),
      300,
    );
    expect(find.textContaining('Arthur’s linked'), findsOneWidget);
  });

  testWidgets('lists the profile’s saved medicines with real counts', (
    tester,
  ) async {
    await pump(tester, const Size(400, 2400));
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Vitamin D3'), findsOneWidget);
    expect(find.text('Low Supply: ~3 doses left'), findsOneWidget);
    expect(find.text('Taken today at 9:08 AM'), findsOneWidget);
    expect(find.text('38 doses remaining'), findsOneWidget);
    await profiles.switchTo('p1');
    await tester.pump();
    await tester.pump();
    expect(find.text('Amoxicillin'), findsNothing);
    expect(find.text('Lisinopril'), findsOneWidget);
  });

  testWidgets('details drawer expands and collapses per medicine', (
    tester,
  ) async {
    await pump(tester, const Size(400, 3000));
    expect(find.text('INSTRUCTIONS'), findsNothing);
    await tester.tap(find.byTooltip('Expand details').first);
    await tester.pump();
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
    expect(find.text('Take with dinner & full glass of water'), findsOneWidget);
    expect(find.text('7-day course'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide details'));
    await tester.pump();
    expect(find.text('INSTRUCTIONS'), findsNothing);
  });

  testWidgets('Log Dose logs the next due occurrence once', (tester) async {
    await pump(tester, const Size(400, 3000));
    await tester.tap(find.text('Log Dose').first);
    await tester.pump();
    await tester.pump();
    expect(careStore.logsOf(uid, 'self').keys, contains('amox_2026-10-24_480'));
    expect(careStore.medicinesOf(uid, 'self')['amox']!.quantity, 2);
    // Vitamin D3's only dose today is already logged.
    expect(find.text('All Logged'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('pause and archive move a medicine to Archived / Paused', (
    tester,
  ) async {
    await pump(tester, const Size(400, 3000));
    await tester.tap(find.byTooltip('Expand details').first);
    await tester.pump();
    await tester.tap(find.text('Pause Reminders'));
    await tester.pump();
    await tester.pump();
    expect(
      careStore.medicinesOf(uid, 'self')['amox']!.status,
      MedicineStatus.paused,
    );
    expect(find.text('Amoxicillin'), findsNothing);

    await tester.tap(find.text('Archived / Paused'));
    await tester.pump();
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Archive Medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(
      careStore.medicinesOf(uid, 'self')['amox']!.status,
      MedicineStatus.archived,
    );
    expect(find.text('Restore Medicine'), findsOneWidget);
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
    final out = Platform.environment['MED_SHOT'];
    if (out == null) return;
    // Tests draw shadows unblurred by default; show them as on device.
    debugDisableShadows = false;
    await pump(tester, const Size(400, 2000));
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
