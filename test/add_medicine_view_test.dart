import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/add_medicine/bindings/add_medicine_binding.dart';
import 'package:dosemate/modules/add_medicine/view_model/add_medicine_view_model.dart';
import 'package:dosemate/modules/add_medicine/views/add_medicine_view.dart';
import 'package:dosemate/modules/home/view_model/home_view_model.dart';
import 'package:dosemate/modules/home/views/home_view.dart';
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
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Size size, {double inset = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    addTearDown(tester.view.reset);
    Get.put(AddMedicineViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: const RepaintBoundary(key: _shot, child: AddMedicineView()),
      ),
    );
    await tester.pump();
  }

  Future<void> openFrom(
    WidgetTester tester,
    Widget origin,
    Finder button,
  ) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: origin,
        getPages: [
          GetPage(
            name: AppRoutes.addMedicine,
            page: () => const AddMedicineView(),
            binding: AddMedicineBinding(),
          ),
        ],
      ),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AddMedicineView), findsOneWidget);
    expect(find.text('Medication Identity'), findsOneWidget);
    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    expect(find.byType(AddMedicineView), findsNothing);
    expect(find.byType(origin.runtimeType), findsOneWidget);
    expect(profiles.activeProfile?.id, UserProfile.selfId);
  }

  testWidgets('Medicines → Add New Medicine opens the form, back returns', (
    tester,
  ) async {
    Get.put(MedicinesViewModel());
    await openFrom(
      tester,
      const MedicinesView(),
      find.text('Add New Medicine'),
    );
  });

  testWidgets('Home → Add Medicine opens the form, back returns', (
    tester,
  ) async {
    Get.put(HomeViewModel());
    await openFrom(tester, const HomeView(), find.text('Add Medicine'));
  });

  testWidgets('Cancel also returns', (tester) async {
    Get.put(MedicinesViewModel());
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const MedicinesView(),
        getPages: [
          GetPage(
            name: AppRoutes.addMedicine,
            page: () => const AddMedicineView(),
            binding: AddMedicineBinding(),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Add New Medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AddMedicineView), findsNothing);
  });

  /// Medicines with the form route, as in the app.
  Future<void> openMedicines(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(MedicinesViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const MedicinesView(),
        getPages: [
          GetPage(
            name: AppRoutes.addMedicine,
            page: () => const AddMedicineView(),
            binding: AddMedicineBinding(),
          ),
        ],
      ),
    );
    await tester.pump();
  }

  Future<void> flushSnackbars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('the assignee is fixed when the form opens', (tester) async {
    await pump(tester, const Size(400, 900));
    expect(find.text('Assign to: Eleanor Vance (Self)'), findsOneWidget);
    // A switch made elsewhere doesn't move this medicine to Arthur.
    await profiles.switchTo('p1');
    await tester.pump();
    expect(find.text('Assign to: Eleanor Vance (Self)'), findsOneWidget);
    expect(Get.find<AddMedicineViewModel>().profileId.value, 'self');
  });

  testWidgets('local form interactions', (tester) async {
    await pump(tester, const Size(400, 3000));
    final vm = Get.find<AddMedicineViewModel>();

    await tester.tap(find.text('Multiple times daily'));
    await tester.tap(find.byTooltip('Remove 08:00 AM'));
    await tester.tap(find.byTooltip('Increase pills'));
    await tester.tap(find.bySemanticsLabel('Low supply warning').last);
    await tester.pump();
    expect(vm.frequency.value, Frequency.multipleDaily);
    expect(find.text('08:00 AM'), findsNothing);
    expect(find.text('1 left'), findsOneWidget);
    expect(vm.lowSupplyWarning.value, isFalse);

    await tester.tap(find.text('Specific days'));
    await tester.pump();
    expect(find.bySemanticsLabel('Monday'), findsOneWidget);

    await tester.tap(find.text('Supply & Refill Tracking'));
    await tester.pump();
    expect(find.text('Quantity on hand'), findsNothing);
  });

  testWidgets('validation keeps the form and saves nothing', (tester) async {
    await openMedicines(tester);
    await tester.tap(find.text('Add New Medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiple times daily'));
    await tester.tap(find.text('Review Details & Save'));
    await tester.pump();
    expect(find.text('Enter the medicine name.'), findsWidgets);
    expect(find.text('Add at least two reminder times.'), findsOneWidget);
    expect(careStore.writes, 0);
    expect(find.byType(AddMedicineView), findsOneWidget);
    await flushSnackbars(tester);
  });

  testWidgets('saving adds it to Medicines immediately, for the profile '
      'the form was opened for', (tester) async {
    await openMedicines(tester);
    await tester.tap(find.text('Add New Medicine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Metformin');
    await tester.enterText(find.byType(TextField).at(1), '500mg');
    await profiles.switchTo('p1'); // e.g. from another screen
    await tester.tap(find.byTooltip('Increase pills'));
    await tester.tap(find.text('Review Details & Save'));
    await tester.tap(find.text('Review Details & Save'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(careStore.creates, 1);
    final saved = careStore
        .medicinesOf(uid, 'self')
        .values
        .firstWhere((m) => m.name == 'Metformin');
    expect(saved.dosage, '500mg');
    expect(saved.doseMinutes, [480]);
    expect(saved.quantity, 1);
    expect(saved.status, MedicineStatus.active);
    expect(careStore.medicinesOf(uid, 'p1').keys, ['lis']);
    expect(find.byType(AddMedicineView), findsNothing);
    await profiles.switchTo('self');
    await tester.pump();
    await tester.pump();
    expect(find.text('Metformin'), findsOneWidget);
    await flushSnackbars(tester);
  });

  testWidgets('a failed save keeps everything entered; retry saves once', (
    tester,
  ) async {
    await openMedicines(tester);
    await tester.tap(find.text('Add New Medicine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Metformin');
    careStore.failNext = const CareFailure(
      "You don't have permission to change this.",
      code: 'permission-denied',
    );
    await tester.tap(find.text('Review Details & Save'));
    await tester.pump();
    expect(find.byType(AddMedicineView), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    await flushSnackbars(tester);

    await tester.tap(find.text('Review Details & Save'));
    await tester.pumpAndSettle();
    expect(careStore.creates, 1);
    expect(find.byType(AddMedicineView), findsNothing);
    await flushSnackbars(tester);
  });

  testWidgets('offline saves are reported as pending, not confirmed', (
    tester,
  ) async {
    await openMedicines(tester);
    await tester.tap(find.text('Add New Medicine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Metformin');
    careStore.offline = true;
    await tester.tap(find.text('Review Details & Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('will sync when you'), findsOneWidget);
    await flushSnackbars(tester);
  });

  testWidgets('edit prefills, saves changes and can delete', (tester) async {
    await openMedicines(tester);
    await tester.tap(find.byTooltip('Expand details').first);
    await tester.pump();
    await tester.tap(find.text('Edit Schedule & Routine'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Medication'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Amoxicillin 250');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(careStore.creates, 0);
    expect(careStore.medicinesOf(uid, 'self')['amox']!.name, 'Amoxicillin 250');
    expect(find.text('Amoxicillin 250'), findsOneWidget);
    await flushSnackbars(tester);

    await tester.tap(find.text('Edit Schedule & Routine'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete Medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Medicine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(careStore.medicinesOf(uid, 'self').containsKey('amox'), isFalse);
    expect(find.text('Amoxicillin 250'), findsNothing);
    await flushSnackbars(tester);
  });

  final realFonts = Platform.environment.containsKey('HOME_FONTS');
  for (final width in [if (realFonts) 320.0, 360.0, 400.0, 600.0]) {
    testWidgets('no overflow at ${width.toInt()}px wide', (tester) async {
      await pump(tester, Size(width, 2600));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard open: no overflow and the field stays visible', (
    tester,
  ) async {
    await pump(tester, const Size(360, 740), inset: 300);
    await tester.showKeyboard(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(TextField).last);
    expect(rect.top, lessThan(740 - 300));
  });

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['ADD_MED_SHOT'];
    if (out == null) return;
    debugDisableShadows = false;
    await pump(tester, const Size(400, 2040));
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
