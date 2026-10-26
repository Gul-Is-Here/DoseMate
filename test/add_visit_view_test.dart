import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/places_repository.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/add_visit/bindings/add_visit_binding.dart';
import 'package:dosemate/modules/add_visit/view_model/add_visit_view_model.dart';
import 'package:dosemate/modules/add_visit/views/add_visit_view.dart';
import 'package:dosemate/modules/home/view_model/home_view_model.dart';
import 'package:dosemate/modules/home/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_care.dart';
import 'support/fake_places.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

const _shot = ValueKey('shot');

void main() {
  const uid = 'uid-1';
  late ProfileService profiles;
  late FakeCare careStore;
  late FakePlaces places;

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
    places = Get.put<PlacesRepository>(FakePlaces()) as FakePlaces;
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Size size, {double inset = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    addTearDown(tester.view.reset);
    Get.put(AddVisitViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: const RepaintBoundary(key: _shot, child: AddVisitView()),
      ),
    );
    await tester.pump();
  }

  testWidgets('Home Add Visit opens the form and back returns', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(HomeViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const HomeView(),
        getPages: [
          GetPage(
            name: AppRoutes.addVisit,
            page: () => const AddVisitView(),
            binding: AddVisitBinding(),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Add Visit').first);
    await tester.pumpAndSettle();
    expect(find.byType(AddVisitView), findsOneWidget);
    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    expect(find.byType(AddVisitView), findsNothing);
    expect(find.byType(HomeView), findsOneWidget);
    // The selected profile is untouched by the round trip.
    expect(profiles.activeProfile?.id, UserProfile.selfId);
  });

  /// Home with the visit route, as in the app.
  Future<void> openHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(HomeViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const HomeView(),
        getPages: [
          GetPage(
            name: AppRoutes.addVisit,
            page: () => const AddVisitView(),
            binding: AddVisitBinding(),
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

  testWidgets('copy names the profile fixed when the form opened', (
    tester,
  ) async {
    await pump(tester, const Size(400, 900));
    expect(find.textContaining('Eleanor Vance’s wellness'), findsOneWidget);
    await profiles.switchTo('p1');
    await tester.pump();
    expect(find.textContaining('Eleanor Vance’s wellness'), findsOneWidget);
    expect(find.textContaining('Choose when Eleanor'), findsOneWidget);
  });

  testWidgets('local selections, toggle and prep pills', (tester) async {
    await pump(tester, const Size(400, 3000));
    final vm = Get.find<AddVisitViewModel>();

    await tester.dragUntilVisible(
      find.text('Specialist'),
      find.byType(ListView),
      const Offset(-100, 0),
    );
    await tester.ensureVisible(find.text('Specialist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Specialist'));
    await tester.tap(find.text('1 hour before'));
    await tester.tap(find.text('1 day before'));
    await tester.tap(find.bySemanticsLabel('Smart Departure Alerts').last);
    await tester.tap(find.text('Fasting required'));
    await tester.pump();
    await tester.tap(find.text('Fasting required').last);
    await tester.pump();

    expect(vm.category.value, 'Specialist');
    expect(vm.reminders, {'1 hour before'});
    expect(vm.departureAlerts.value, isTrue);
    expect(vm.notes.text, 'Fasting required');
  });

  testWidgets('validation: title required, time in the future, phone', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tap(find.text('Add Visit').first);
    await tester.pumpAndSettle();
    final vm = Get.find<AddVisitViewModel>();
    vm.setDate(DateTime(2026, 10, 24));
    vm.setTime(const TimeOfDay(hour: 9, minute: 0)); // before "now" (2 PM)
    vm.phone.text = 'call me';
    await tester.tap(find.text('Save Appointment'));
    await tester.pump();
    expect(find.text('Enter what the appointment is for.'), findsWidgets);
    expect(find.text('Choose a date and time in the future.'), findsOneWidget);
    expect(find.text('Enter a valid phone number.'), findsOneWidget);
    expect(careStore.writes, 0);
    await flushSnackbars(tester);
  });

  testWidgets('a saved visit becomes the next appointment on Home, in order', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tap(find.text('Add Visit').first);
    await tester.pumpAndSettle();
    final vm = Get.find<AddVisitViewModel>();
    vm.title.text = 'Cardiology Follow-up';
    vm.doctor.text = 'Dr. Lee';
    vm.setDate(DateTime(2026, 10, 26));
    vm.setTime(const TimeOfDay(hour: 10, minute: 15));
    await profiles.switchTo('p1'); // must not move the visit
    await tester.tap(find.text('Save Appointment'));
    await tester.tap(find.text('Save Appointment'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(careStore.creates, 1);
    expect(careStore.visitsOf(uid, 'p1'), isEmpty);
    final saved = careStore
        .visitsOf(uid, 'self')
        .values
        .firstWhere((v) => v.title == 'Cardiology Follow-up');
    expect(saved.startsAt, DateTime(2026, 10, 26, 10, 15));
    expect(find.byType(AddVisitView), findsNothing);

    await profiles.switchTo('self');
    await tester.pump();
    await tester.pump();
    // Sooner than the Thursday dentist visit, so it is shown next.
    expect(find.text('Cardiology Follow-up'), findsOneWidget);
    expect(find.text('Monday • 10:15 AM'), findsOneWidget);
    expect(find.text('In 2 days'), findsOneWidget);
    await flushSnackbars(tester);
  });

  Finder addressField() => find.byWidgetPredicate(
    (w) =>
        w is TextField && w.controller == Get.find<AddVisitViewModel>().address,
  );

  testWidgets('address search: debounced, outdated replies ignored, selection '
      'fills the field and edits clear it', (tester) async {
    await pump(tester, const Size(400, 3000));
    final vm = Get.find<AddVisitViewModel>();

    await tester.enterText(addressField(), 'St');
    await tester.pump(const Duration(seconds: 1));
    expect(places.searches, isEmpty); // too short

    await tester.enterText(addressField(), 'St J');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(addressField(), 'St Jude');
    await tester.pump(const Duration(milliseconds: 200));
    expect(places.searches, isEmpty); // still debouncing
    await tester.pump(const Duration(milliseconds: 200));
    expect(places.searches.map((s) => s.input), ['St Jude']);
    expect(find.bySemanticsLabel('Searching places'), findsOneWidget);

    // A newer search starts; the older reply arrives late and is ignored.
    await tester.enterText(addressField(), 'St Jude Dental');
    await tester.pump(const Duration(milliseconds: 400));
    places.searches[0].reply.complete(const [
      PlaceSuggestion(placeId: 'old', name: 'Old result', address: 'Old'),
    ]);
    await tester.pump();
    expect(find.text('Old result'), findsNothing);
    expect(places.searches[1].token, places.searches[0].token);
    places.searches[1].reply.complete(const [stJude]);
    await tester.pump();
    expect(find.text('St. Jude Dental Clinic'), findsOneWidget);
    expect(find.text('120 Medical Center Dr, Fullerton, CA, USA'), findsOne);

    await tester.tap(find.text('St. Jude Dental Clinic'));
    await tester.pump();
    expect(places.detailRequests.single.token, places.searches[1].token);
    expect(vm.address.text, '120 Medical Center Dr, Fullerton, CA 92835, USA');
    expect(vm.selectedPlace.value?.latitude, 33.8823);
    expect(find.text('Old result'), findsNothing);

    // Editing after selecting drops the place and coordinates.
    await tester.enterText(addressField(), '${vm.address.text} Suite 4');
    await tester.pump();
    expect(vm.selectedPlace.value, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    // A new session after the previous one ended with details.
    expect(places.searches.last.token, isNot(places.searches[1].token));
    places.searches.last.reply.complete(const []);
    await tester.pump();
    expect(find.textContaining('No matching places'), findsOneWidget);
  });

  testWidgets('search errors show a message and retry', (tester) async {
    await pump(tester, const Size(400, 3000));
    await tester.enterText(addressField(), 'Clinic');
    await tester.pump(const Duration(milliseconds: 400));
    places.searches.single.reply.completeError(
      const PlacesFailure("You're offline. You can still type the address."),
    );
    await tester.pump();
    expect(find.textContaining("You're offline"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(places.searches, hasLength(2));
    places.searches.last.reply.complete(const [stJude]);
    await tester.pump();
    expect(find.text('St. Jude Dental Clinic'), findsOneWidget);
  });

  testWidgets('a failed place lookup retries that lookup, not the search', (
    tester,
  ) async {
    await pump(tester, const Size(400, 3000));
    final vm = Get.find<AddVisitViewModel>();
    vm.title.text = 'Cleaning';
    vm.clinic.text = 'My dentist';
    await tester.enterText(addressField(), 'St Jude');
    await tester.pump(const Duration(milliseconds: 400));
    places.searches.single.reply.complete(const [stJude]);
    await tester.pump();

    places.detailsFailure = const PlacesFailure(
      'Address search is taking too long.',
      code: 'timeout',
      kind: PlacesErrorKind.network,
    );
    await tester.tap(find.text('St. Jude Dental Clinic'));
    await tester.pump();
    expect(find.text('Address search is taking too long.'), findsOneWidget);
    // The suggestion is still there to try again or pick another.
    expect(find.text('St. Jude Dental Clinic'), findsOneWidget);
    expect(vm.selectedPlace.value, isNull);

    places.detailsFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(places.searches, hasLength(1)); // no new search
    expect(places.detailRequests.map((r) => r.placeId), [
      'place-stjude',
      'place-stjude',
    ]);
    expect(places.detailRequests.last.token, places.detailRequests.first.token);
    expect(vm.selectedPlace.value?.placeId, 'place-stjude');
    expect(vm.selectedPlace.value?.longitude, -117.9256);
    expect(vm.address.text, '120 Medical Center Dr, Fullerton, CA 92835, USA');
    // What was typed is kept: the title, and the clinic name.
    expect(vm.title.text, 'Cleaning');
    expect(vm.clinic.text, 'My dentist');
  });

  testWidgets('setup and key errors explain themselves without a Retry', (
    tester,
  ) async {
    await pump(tester, const Size(400, 3000));
    final vm = Get.find<AddVisitViewModel>();
    vm.title.text = 'Cleaning';
    await tester.enterText(addressField(), 'Clinic Road 4');
    await tester.pump(const Duration(milliseconds: 400));
    places.searches.single.reply.completeError(
      const PlacesFailure(
        'Address search isn’t set up yet. You can still type the address.',
        code: 'SERVICE_DISABLED',
        kind: PlacesErrorKind.config,
      ),
    );
    await tester.pump();
    expect(find.textContaining('isn’t set up yet'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('No matching places'), findsNothing);
    expect(vm.address.text, 'Clinic Road 4');
    expect(vm.title.text, 'Cleaning');
    // Typing more still searches again.
    await tester.enterText(addressField(), 'Clinic Road 45');
    await tester.pump(const Duration(milliseconds: 400));
    expect(places.searches, hasLength(2));
  });

  testWidgets('the chosen place is saved and comes back when reopened', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tap(find.text('Add Visit').first);
    await tester.pumpAndSettle();
    final vm = Get.find<AddVisitViewModel>();
    vm.title.text = 'Cleaning';
    vm.setDate(DateTime(2026, 10, 25));
    await tester.enterText(addressField(), 'St Jude');
    await tester.pump(const Duration(milliseconds: 400));
    places.searches.single.reply.complete(const [stJude]);
    await tester.pump();
    await tester.tap(find.text('St. Jude Dental Clinic'));
    await tester.pump();
    await tester.tap(find.text('Save Appointment'));
    await tester.pumpAndSettle();

    final saved = careStore
        .visitsOf(uid, 'self')
        .values
        .firstWhere((v) => v.title == 'Cleaning');
    expect(saved.address, '120 Medical Center Dr, Fullerton, CA 92835, USA');
    expect(saved.place?.placeId, 'place-stjude');
    expect(saved.place?.name, 'St. Jude Dental Clinic');
    expect(saved.place?.latitude, 33.8823);
    expect(saved.place?.longitude, -117.9256);
    // Round trip through the stored fields.
    final stored = Visit.fromMap(
      saved.id,
      {
        ...saved.toWriteMap(),
      }..removeWhere((_, v) => v.runtimeType.toString().contains('FieldValue')),
    );
    expect(stored.place?.latitude, 33.8823);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Reopen from Home: address, place and coordinates are preserved.
    await tester.tap(find.byTooltip('Appointment notes'));
    await tester.pumpAndSettle();
    final edit = Get.find<AddVisitViewModel>();
    expect(
      edit.address.text,
      '120 Medical Center Dr, Fullerton, CA 92835, USA',
    );
    expect(edit.selectedPlace.value?.placeId, 'place-stjude');
    expect(places.searches, hasLength(1)); // reopening doesn't search
    // The place's name filled the empty clinic field and labels the map.
    expect(edit.clinic.text, 'St. Jude Dental Clinic');
    expect(saved.clinic, 'St. Jude Dental Clinic');
    expect(find.text('St. Jude Dental Clinic'), findsNWidgets(2));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(
      careStore.visitsOf(uid, 'self')[saved.id]!.place?.longitude,
      -117.9256,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('edit from Home, then cancel removes it from upcoming', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tap(find.byTooltip('Appointment notes'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Visit'), findsOneWidget);
    final vm = Get.find<AddVisitViewModel>();
    expect(vm.title.text, 'Dentist Checkup & Cleaning');
    vm.title.text = 'Dentist Cleaning';
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(careStore.creates, 0);
    expect(find.text('Dentist Cleaning'), findsOneWidget);
    await flushSnackbars(tester);

    await tester.tap(find.byTooltip('Appointment notes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancel Visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel Visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel Visit').last);
    await tester.pumpAndSettle();
    expect(
      careStore.visitsOf(uid, 'self')['dentist']!.status,
      VisitStatus.cancelled,
    );
    expect(find.text('Next Appointment'), findsNothing);
    await flushSnackbars(tester);
    expect(find.text('Dentist Cleaning'), findsNothing);
  });

  final realFonts = Platform.environment.containsKey('HOME_FONTS');
  for (final width in [if (realFonts) 320.0, 360.0, 400.0, 600.0]) {
    testWidgets('no overflow at ${width.toInt()}px wide', (tester) async {
      await pump(tester, Size(width, 2400));
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
    final out = Platform.environment['ADD_SHOT'];
    if (out == null) return;
    debugDisableShadows = false;
    await pump(tester, const Size(400, 2230));
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
