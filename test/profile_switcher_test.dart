import 'dart:async';

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/profile_setup/view_model/profile_setup_view_model.dart';
import 'package:dosemate/widgets/profile_switcher_sheet.dart';
import 'package:dosemate/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_profiles.dart';

void main() {
  const uid = 'uid-1';
  late FakeProfiles store;
  late ProfileService service;
  Object? editorArgs;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    Get.testMode = true;
    store = FakeProfiles();
    service = Get.put(ProfileService(store));
    editorArgs = null;
  });

  tearDown(Get.reset);

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: AppRoutes.profileSetup,
            page: () {
              editorArgs = Get.arguments;
              return const Text('EDITOR');
            },
          ),
        ],
        home: const Scaffold(body: Text('HOME')),
      ),
    );
    ProfileSwitcherSheet.show();
    // A spinner never settles, so loading states pump for a fixed time.
    settle
        ? await tester.pumpAndSettle()
        : await tester.pump(const Duration(seconds: 1));
  }

  const self = UserProfile(
    id: UserProfile.selfId,
    type: ProfileType.self,
    fullName: 'Eleanor Vance',
  );
  const parent = UserProfile(
    id: 'p1',
    type: ProfileType.parent,
    fullName: 'Ruth Vance',
    relationship: 'Mother / Senior Parent',
  );

  testWidgets('shows a loading state while profiles load', (tester) async {
    service.status.value = ProfilesStatus.loading;
    await open(tester, settle: false);
    // Placeholder rows shaped like profiles, not a spinner.
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.byType(Bone), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Stop the endless shimmer before the test ends.
    Get.back();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('shows an error with a working retry', (tester) async {
    store.readFailure = const ProfileFailure("You're offline.");
    await service.start(uid, selfName: 'Eleanor Vance');
    await open(tester);
    expect(find.text("You're offline."), findsOneWidget);

    store
      ..readFailure = null
      ..put(uid, self);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Eleanor Vance'), findsOneWidget);
  });

  testWidgets('shows an empty state that leads to setup', (tester) async {
    await service.start(uid, selfName: 'Eleanor Vance');
    await open(tester);
    expect(find.text("You haven't set up a profile yet."), findsOneWidget);
    await tester.tap(find.text('Set up my profile'));
    await tester.pumpAndSettle();
    expect(find.text('EDITOR'), findsOneWidget);
    expect((editorArgs! as ProfileEditorArgs).profileId, isNull);
  });

  testWidgets(
    'lists each profile with name and relationship, marking the active one',
    (tester) async {
      store
        ..put(uid, self)
        ..put(uid, parent);
      await service.start(uid, selfName: 'Eleanor Vance');
      await open(tester);
      expect(find.text('Eleanor Vance'), findsOneWidget);
      expect(find.text('Myself'), findsOneWidget);
      expect(find.text('Ruth Vance'), findsOneWidget);
      expect(find.text('Parent · Mother / Senior Parent'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      final activeTile = find
          .ancestor(of: find.text('Active'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: activeTile, matching: find.text('Eleanor Vance')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a profile switches to it and remembers the choice', (
    tester,
  ) async {
    store
      ..put(uid, self)
      ..put(uid, parent);
    await service.start(uid, selfName: 'Eleanor Vance');
    await open(tester);
    await tester.tap(find.text('Ruth Vance'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSwitcherSheet), findsNothing);
    expect(service.activeProfile!.id, 'p1');
    expect(store.accounts[uid]!.activeProfileId, 'p1');
  });

  testWidgets('edit and add open the editor for the right profile', (
    tester,
  ) async {
    store
      ..put(uid, self)
      ..put(uid, parent);
    await service.start(uid, selfName: 'Eleanor Vance');
    await open(tester);
    await tester.tap(find.byTooltip('Edit Ruth Vance'));
    await tester.pumpAndSettle();
    expect((editorArgs! as ProfileEditorArgs).profileId, 'p1');

    Get.back();
    await tester.pumpAndSettle();
    ProfileSwitcherSheet.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spouse'));
    await tester.pumpAndSettle();
    expect((editorArgs! as ProfileEditorArgs).newType, ProfileType.spouse);
  });
}
