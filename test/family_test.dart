import 'dart:io';
import 'dart:ui' as ui;

import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/modules/family/view_model/family_view_model.dart';
import 'package:dosemate/modules/family/views/family_view.dart';
import 'package:dosemate/modules/profile_setup/view_model/profile_setup_view_model.dart';
import 'package:dosemate/widgets/profile_switcher_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

const _shot = ValueKey('shot');

class _MailUser extends FakeUser {
  @override
  String? get email => 'eleanor@example.com';
}

void main() {
  const uid = 'uid-1';
  late FakeProfiles store;
  late ProfileService profiles;
  late FakeCare careStore;
  late CareService care;

  /// Arthur's profile, owned by another account and shared with uid-1.
  final shared = UserProfile.shared({
    'ownerUid': 'owner9',
    'profileId': 'self',
    'profileName': 'Arthur Vance',
    'ownerName': 'Sam Vance',
    'permissions': {'checklist': true, 'alerts': false, 'appointments': false},
  });

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
          type: ProfileType.parent,
          fullName: 'Ruth Vance',
          relationship: 'Mother / Senior Parent',
        ),
      );
    profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    final auth = Get.put(AuthService(AuthRepository(NoAuth()), profiles));
    auth.user.value = _MailUser();
    careStore = FakeCare();
    seedCare(careStore);
    care = putCare(profiles, careStore, now: fixedNow);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  /// Opened editor routes, with their arguments.
  final opened = <Object?>[];

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened.clear();
    Get.put(FamilyViewModel());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const RepaintBoundary(key: _shot, child: FamilyView()),
        getPages: [
          GetPage(
            name: AppRoutes.profileSetup,
            page: () {
              opened.add(Get.arguments);
              return const Scaffold(body: Text('Profile editor'));
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inList(String text) =>
      find.descendant(of: find.byType(ListView), matching: find.text(text));

  group('screen', () {
    testWidgets('lists only the owner’s profiles; no caretaker invites', (
      tester,
    ) async {
      store.share(uid, shared);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await open(tester);
      expect(find.text('Family Profiles'), findsOneWidget);
      expect(find.text('Your Profiles'), findsOneWidget);
      expect(find.text('2 Profiles'), findsOneWidget);
      expect(inList('Eleanor Vance'), findsOneWidget);
      expect(find.text('(Self)'), findsOneWidget);
      expect(find.text('Account owner'), findsOneWidget);
      expect(inList('Ruth Vance'), findsOneWidget);
      expect(
        find.text('Managed by you · Parent · Mother / Senior Parent'),
        findsOneWidget,
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Currently managing'), findsOneWidget);
      expect(find.text('Switch to Ruth'), findsOneWidget);
      expect(
        find.text(
          'Only you, the account owner, can see and manage these profiles.',
        ),
        findsOneWidget,
      );
      // Profiles shared by other accounts aren't managed here.
      expect(inList('Arthur Vance'), findsNothing);
      // The caretaker invitation feature is gone.
      for (final gone in [
        'Send Protected Invitation',
        'Invite New Caregiver',
        'Circle Members',
        'Resend Invite',
        'Manage Permissions',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('switching makes that profile active and remembers it', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Switch to Ruth'));
      await tester.pumpAndSettle();
      expect(profiles.activeProfileId.value, 'p1');
      expect(store.accounts[uid]!.activeProfileId, 'p1');
      expect(find.text('Switch to Eleanor'), findsOneWidget);
      expect(find.text('Switch to Ruth'), findsNothing);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('a failure to remember the switch is reported, not undone', (
      tester,
    ) async {
      await open(tester);
      store.saveFailure = const ProfileFailure('Offline.');
      await tester.tap(find.text('Switch to Ruth'));
      await tester.pumpAndSettle();
      expect(profiles.activeProfileId.value, 'p1');
      expect(find.text('Switched profile'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('edit and add open the profile editor', (tester) async {
      await open(tester);
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();
      expect(find.text('Profile editor'), findsOneWidget);
      expect((opened.single! as ProfileEditorArgs).profileId, 'p1');
      Get.back<void>();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Add Spouse profile'));
      await tester.tap(find.byTooltip('Add Spouse profile'));
      await tester.pumpAndSettle();
      expect((opened.last! as ProfileEditorArgs).newType, ProfileType.spouse);
    });

    testWidgets('new profiles show up live', (tester) async {
      await open(tester);
      store.put(
        uid,
        const UserProfile(
          id: 'p2',
          type: ProfileType.spouse,
          fullName: 'Tom Vance',
          relationship: 'Spouse or Partner',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 Profiles'), findsOneWidget);
      expect(inList('Tom Vance'), findsOneWidget);
    });

    testWidgets('small screen: no overflow', (tester) async {
      await open(tester, size: const Size(320, 1800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reference-size screenshot', (tester) async {
      final out = Platform.environment['FAMILY_SHOT'];
      if (out == null) return;
      debugDisableShadows = false;
      await open(tester, size: const Size(400, 1250));
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

  group('shared profile data', () {
    test(
      'appears in the switcher list and reads only what was granted',
      () async {
        careStore.medicinesOf('owner9', 'self')['m1'] = Medicine(
          id: 'm1',
          name: 'Metformin',
          frequency: Frequency.onceDaily,
          doseMinutes: const [480],
          startDate: DateTime(2026, 10, 1),
          courseDays: 90,
        );
        careStore.visitsOf('owner9', 'self')['v1'] = Visit(
          id: 'v1',
          title: 'Private visit',
          category: 'Dentist',
          startsAt: DateTime(2026, 10, 30, 9),
        );
        store.share(uid, shared);
        await Future<void>.delayed(Duration.zero);
        expect(profiles.shared.single.fullName, 'Arthur Vance');
        expect(profiles.profiles.length, 2); // not copied into own profiles

        await profiles.switchTo(shared.id);
        await Future<void>.delayed(Duration.zero);
        expect(care.isShared, isTrue);
        expect(care.dataUid, 'owner9');
        expect(care.dataPid, 'self');
        expect(care.status.value, CareStatus.ready);
        expect(care.medicines.single.name, 'Metformin');
        // No appointment permission: no visits, and no query for them.
        expect(care.visits, isEmpty);

        // View-only: writes are refused before reaching Firestore.
        final writes = careStore.writes;
        await expectLater(
          care.logDose(
            DoseOccurrence(care.medicines.single, DateTime(2026, 10, 24), 480),
            DoseStatus.taken,
          ),
          throwsA(isA<CareFailure>()),
        );
        expect(
          () => care.saveVisit(
            shared.id,
            Visit(
              id: 'x',
              title: 'X',
              category: '',
              startsAt: DateTime(2026, 11, 1),
            ),
            isNew: true,
          ),
          throwsA(isA<CareFailure>()),
        );
        expect(careStore.writes, writes);

        // Owner revokes: back to own data immediately.
        store.unshare(uid, shared.id);
        await Future<void>.delayed(Duration.zero);
        expect(care.isShared, isFalse);
        expect(care.dataUid, uid);
        expect(care.medicines.map((m) => m.name), isNot(contains('Metformin')));
      },
    );

    test('appointment access reads and writes the owner’s visits', () async {
      careStore.visitsOf('owner9', 'self')['v1'] = Visit(
        id: 'v1',
        title: 'Physio',
        category: 'Specialist',
        startsAt: DateTime(2026, 10, 30, 9),
      );
      final withVisits = UserProfile.shared({
        'ownerUid': 'owner9',
        'profileId': 'self',
        'profileName': 'Arthur Vance',
        'ownerName': 'Sam Vance',
        'permissions': {'appointments': true},
      });
      store.share(uid, withVisits);
      await Future<void>.delayed(Duration.zero);
      await profiles.switchTo(withVisits.id);
      await Future<void>.delayed(Duration.zero);
      expect(care.visits.single.title, 'Physio');
      expect(care.medicines, isEmpty); // no checklist permission
      await care.saveVisit(
        withVisits.id,
        Visit(
          id: 'v2',
          title: 'Eye exam',
          category: '',
          startsAt: DateTime(2026, 11, 2),
        ),
        isNew: true,
      );
      expect(careStore.visitsOf('owner9', 'self').containsKey('v2'), isTrue);
      expect(careStore.visitsOf(uid, withVisits.id), isEmpty);
      expect(
        () => care.deleteVisit(withVisits.id, 'v1'),
        throwsA(isA<CareFailure>()),
      );
    });

    testWidgets('switcher lists shared profiles without edit', (tester) async {
      Get.put(profiles);
      store.share(uid, shared);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpWidget(
        const GetMaterialApp(home: Scaffold(body: ProfileSwitcherSheet())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Arthur Vance'), findsOneWidget);
      expect(find.text('Shared by Sam Vance'), findsOneWidget);
      expect(find.byTooltip('Edit Arthur Vance'), findsNothing);
      expect(find.byTooltip('Edit Eleanor Vance'), findsOneWidget);
    });
  });
}
