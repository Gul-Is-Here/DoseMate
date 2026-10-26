import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/visit_details/bindings/visit_details_binding.dart';
import 'package:dosemate/modules/visit_details/view_model/visit_details_view_model.dart';
import 'package:dosemate/modules/visit_details/views/visit_details_view.dart';
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
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  Future<void> open(
    WidgetTester tester, {
    String visitId = 'dentist',
    Size size = const Size(400, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('origin')),
        getPages: [
          GetPage(
            name: AppRoutes.visitDetails,
            page: () =>
                const RepaintBoundary(key: _shot, child: VisitDetailsView()),
            binding: VisitDetailsBinding(),
          ),
          GetPage(
            name: AppRoutes.addVisit,
            page: () => const Scaffold(body: Text('page:edit')),
          ),
        ],
      ),
    );
    Get.toNamed(
      AppRoutes.visitDetails,
      arguments: VisitDetailsArgs(visitId: visitId, profileId: 'self'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved appointment', (tester) async {
    await open(tester);
    expect(find.text('Appointment Details'), findsOneWidget);
    expect(find.text('IN 5 DAYS'), findsOneWidget);
    expect(find.text('Dentist Checkup & Cleaning'), findsOneWidget);
    expect(find.text('Dentist'), findsOneWidget);
    expect(find.text('Dr. Robert Sterling'), findsOneWidget);
    expect(find.text('Thursday, Oct 29'), findsOneWidget);
    expect(find.text('3:30 PM'), findsOneWidget);
    expect(find.text('(Afternoon)'), findsOneWidget);
    expect(find.text('St. Jude Dental Clinic'), findsOneWidget);
    expect(find.text('(555) 234-5678'), findsOneWidget);
    // Nothing saved for these, so no empty cards.
    expect(find.text('REMINDERS'), findsNothing);
    expect(find.text('NOTES FOR THIS VISIT'), findsNothing);
  });

  testWidgets('updates live when the visit is edited elsewhere', (
    tester,
  ) async {
    await open(tester);
    final care = Get.find<CareService>();
    await care.saveVisit(
      'self',
      Visit(
        id: 'dentist',
        title: 'Root Canal Follow-up',
        category: 'Dentist',
        startsAt: DateTime(2026, 10, 29, 9),
        clinic: 'St. Jude Dental Clinic',
        notes: 'Bring X-rays',
        reminders: const ['1 day before'],
        departureAlerts: true,
      ),
      isNew: false,
    );
    await flush(tester);
    expect(find.text('Root Canal Follow-up'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('(Morning)'), findsOneWidget);
    expect(find.text('Bring X-rays'), findsOneWidget);
    expect(find.text('1 day before'), findsOneWidget);
    expect(find.text('Departure alerts on'), findsOneWidget);
    // Phone was removed, so its card goes too.
    expect(find.text('Call Office'), findsNothing);
  });

  testWidgets('cancel asks first, then closes and cancels', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Cancel Visit'));
    await tester.tap(find.text('Cancel Visit'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this visit?'), findsOneWidget);
    await tester.tap(find.text('Cancel Visit').last);
    await flush(tester);
    expect(find.text('origin'), findsOneWidget);
    expect(
      careStore.visitsOf(uid, 'self')['dentist']!.status,
      VisitStatus.cancelled,
    );
  });

  testWidgets('edit opens Add Visit with this visit', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Edit Appointment'));
    await tester.tap(find.text('Edit Appointment'));
    await tester.pumpAndSettle();
    expect(find.text('page:edit'), findsOneWidget);
    expect((Get.arguments as Visit).id, 'dentist');
  });

  testWidgets('a missing visit shows a message, not a crash', (tester) async {
    await open(tester, visitId: 'nope');
    expect(
      find.text('This appointment is no longer scheduled'),
      findsOneWidget,
    );
    await tester.tap(find.text('Go Back'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
  });

  testWidgets('switching profile closes it', (tester) async {
    await open(tester);
    await profiles.switchTo('p1');
    await flush(tester);
    expect(find.text('origin'), findsOneWidget);
    expect(find.text('Dentist Checkup & Cleaning'), findsNothing);
  });

  testWidgets('reference-size screenshot', (tester) async {
    final out = Platform.environment['VISIT_SHOT'];
    if (out == null) return;
    careStore.visitsOf(uid, 'self')['dentist'] = Visit(
      id: 'dentist',
      title: 'Dentist Checkup & Cleaning',
      category: 'Dentist',
      startsAt: DateTime(2026, 10, 29, 15, 30),
      doctor: 'Dr. Robert Sterling',
      clinic: 'St. Jude Dental Clinic',
      address: '1200 Market St, San Francisco, CA',
      phone: '(555) 234-5678',
      notes: 'Bring insurance card. Ask about the sensitive molar.',
      reminders: const ['1 day before', '1 hour before'],
      departureAlerts: true,
    );
    await Get.find<CareService>().retry();
    debugDisableShadows = false;
    await open(tester, size: const Size(400, 1300));
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
