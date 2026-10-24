import 'dart:async';
import 'dart:io';

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/profile_setup/view_model/profile_setup_view_model.dart';
import 'package:dosemate/modules/profile_setup/views/profile_setup_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_image_picker.dart';
import 'support/fake_profiles.dart';

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'uid-1';

  @override
  String? get displayName => 'Eleanor Vance';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeProfiles profiles;
  late FakeImagePicker picker;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    Get.testMode = true;
    profiles = FakeProfiles();
    picker = FakeImagePicker();
    Get.put(AuthService(AuthRepository(_NoAuth()), ProfileService(profiles)))
            .user
            .value =
        _User();
  });

  tearDown(Get.reset);

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    double keyboard = 0,
    ProfileEditorArgs? args,
  }) async {
    Get.put(ProfileSetupViewModel(picker: picker, args: args));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoutes.profileSetup,
        getPages: [
          GetPage(
            name: AppRoutes.profileSetup,
            page: () => MediaQuery(
              data: MediaQueryData(
                size: size,
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: const ProfileSetupView(),
            ),
          ),
          GetPage(name: AppRoutes.home, page: () => const Text('HOME')),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  ProfileSetupViewModel vm() => Get.find<ProfileSetupViewModel>();

  /// GetX snackbars animate on timers; close them before the test ends.
  Future<void> closeSnackbars(WidgetTester tester) async {
    // Drain the queue: closing one can start the next.
    for (var i = 0; i < 3; i++) {
      Get.closeAllSnackbars();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 5));
  }

  for (final size in const [Size(320, 568), Size(390, 844), Size(820, 1180)]) {
    testWidgets('renders without overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      await pump(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.text('Who are we caring for?'), findsOneWidget);
    });
  }

  testWidgets('stays scrollable with the keyboard open', (tester) async {
    await pump(tester, const Size(390, 844), keyboard: 336);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save & Continue'), findsOneWidget);
    await closeSnackbars(tester);
  });

  testWidgets('no back button right after sign in', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(find.byTooltip('Go back'), findsNothing);
    await closeSnackbars(tester);
  });

  testWidgets('relationship field only shows for a loved one', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(find.text('Relationship to Caregiver'), findsNothing);
    vm().selectProfileFor(AccountFor.caregiver);
    await tester.pumpAndSettle();
    expect(find.text('Relationship to Caregiver'), findsOneWidget);
    await closeSnackbars(tester);
  });

  testWidgets('Skip goes Home without saving', (tester) async {
    await pump(tester, const Size(390, 844));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(profiles.profilesOf('uid-1'), isEmpty);
    await closeSnackbars(tester);
  });

  testWidgets('Save & Continue saves the profile and goes Home', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    vm()
      ..selectProfileFor(AccountFor.caregiver)
      ..selectRelationship('Grandparent');
    vm().nameController.text = 'Ruth Vance';
    vm().contactPhoneController.text = '(555) 432-8921';
    await vm().saveAndContinue();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    final saved = profiles
        .profilesOf('uid-1')
        .values
        .singleWhere((p) => !p.isSelf);
    expect(saved.fullName, 'Ruth Vance');
    expect(saved.type, ProfileType.other);
    expect(saved.toWriteMap()['relationship'], 'Grandparent');
    expect(saved.toWriteMap()['emergencyContactPhone'], '(555) 432-8921');
    // The account holder still gets their own Myself profile.
    expect(
      profiles.profilesOf('uid-1')[UserProfile.selfId]!.fullName,
      'Eleanor Vance',
    );
    expect(profiles.accounts['uid-1']!.setupCompleted, isTrue);
    await closeSnackbars(tester);
  });

  testWidgets('invalid fields are not saved', (tester) async {
    await pump(tester, const Size(390, 844));
    vm().nameController.text = '  ';
    await vm().saveAndContinue();
    vm().nameController.text = 'Eleanor';
    vm().contactPhoneController.text = '12ab';
    await vm().saveAndContinue();
    await tester.pump(const Duration(seconds: 4));
    expect(profiles.profilesOf('uid-1'), isEmpty);
    expect(find.text('HOME'), findsNothing);
    await closeSnackbars(tester);
  });

  testWidgets('save errors keep the user on the screen', (tester) async {
    await pump(tester, const Size(390, 844));
    profiles.saveFailure = const ProfileFailure('No internet connection.');
    await vm().saveAndContinue();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('HOME'), findsNothing);
    expect(vm().isSaving.value, isFalse);
    await closeSnackbars(tester);
  });

  testWidgets('a second tap while saving is ignored', (tester) async {
    await pump(tester, const Size(390, 844));
    profiles.pendingSave = Completer();
    final first = vm().saveAndContinue();
    await tester.pump();
    expect(vm().isSaving.value, isTrue);
    await vm().saveAndContinue();
    vm().skip();
    expect(profiles.uploads, isEmpty);
    profiles.pendingSave!.complete();
    await first;
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    await closeSnackbars(tester);
  });

  testWidgets('loads saved values into the fields for editing', (tester) async {
    profiles.put(
      'uid-1',
      UserProfile(
        id: 'p1',
        type: ProfileType.parent,
        fullName: 'Ruth Vance',
        relationship: 'Grandparent',
        dateOfBirth: DateTime(1948, 6, 14),
        emergencyContactName: 'Dr. Robert Vance (Son)',
        emergencyContactPhone: '(555) 432-8921',
      ),
    );
    await pump(
      tester,
      const Size(390, 844),
      args: const ProfileEditorArgs.edit('p1'),
    );
    expect(vm().nameController.text, 'Ruth Vance');
    expect(vm().profileFor.value, AccountFor.caregiver);
    expect(vm().relationship.value, 'Grandparent');
    expect(find.text('06/14/1948'), findsOneWidget);
    expect(vm().contactPhoneController.text, '(555) 432-8921');

    vm().nameController.text = 'Ruth A. Vance';
    await vm().saveAndContinue();
    await tester.pumpAndSettle();
    final saved = profiles.profilesOf('uid-1')['p1']!;
    expect(saved.fullName, 'Ruth A. Vance');
    expect(saved.type, ProfileType.parent);
    expect(saved.emergencyContactName, 'Dr. Robert Vance (Son)');
    await closeSnackbars(tester);
  });

  testWidgets('a picked photo is uploaded on save and shown app-wide', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    vm().pendingPhoto.value = File('picked.jpg');
    await vm().saveAndContinue();
    await tester.pumpAndSettle();
    expect(profiles.uploads, ['users/uid-1/profiles/self/avatar_1.jpg']);
    expect(
      Get.find<AuthService>().profiles.selfProfile!.photoUrl,
      contains('avatar_1.jpg'),
    );
    await closeSnackbars(tester);
  });

  testWidgets('a failed save keeps the entered values and picked photo', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    profiles.saveFailure = const ProfileFailure('offline');
    vm().nameController.text = 'Typed Name';
    vm().pendingPhoto.value = File('picked.jpg');
    await vm().saveAndContinue();
    await tester.pump(const Duration(seconds: 4));
    expect(vm().nameController.text, 'Typed Name');
    expect(vm().pendingPhoto.value, isNotNull);
    expect(profiles.deleted, profiles.uploads);
    await closeSnackbars(tester);
  });

  testWidgets('a missing profile shows editable defaults, not an error', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    expect(vm().loadError.value, isNull);
    expect(find.text('Try again'), findsNothing);
    expect(vm().nameController.text, 'Eleanor Vance');
    await closeSnackbars(tester);
  });

  testWidgets(
    'a load failure is shown inline and blocks overwriting saved data',
    (tester) async {
      profiles.readFailure = const ProfileFailure(
        'You\'re offline.',
        code: 'unavailable',
      );
      await pump(tester, const Size(390, 844));
      expect(find.text("You're offline."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await vm().saveAndContinue();
      await tester.pump();
      expect(
        profiles.profilesOf('uid-1'),
        isEmpty,
        reason: 'must not save over an unloaded profile',
      );

      profiles
        ..readFailure = null
        ..put(
          'uid-1',
          const UserProfile(
            id: UserProfile.selfId,
            type: ProfileType.self,
            fullName: 'Saved Name',
            emergencyContactName: 'Kept Contact',
          ),
        );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(vm().nameController.text, 'Saved Name');
      expect(vm().contactNameController.text, 'Kept Contact');
      await closeSnackbars(tester);
    },
  );

  Future<void> openSheet(WidgetTester tester) async {
    // Centre it so the translucent header doesn't cover the tap target.
    await Scrollable.ensureVisible(
      tester.element(find.text('Choose picture')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose picture'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the photo offers Take Photo and Choose from Gallery', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    await openSheet(tester);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await closeSnackbars(tester);
  });

  for (final (label, source) in [
    ('Take Photo', ImageSource.camera),
    ('Choose from Gallery', ImageSource.gallery),
  ]) {
    testWidgets('$label previews the picked photo immediately', (tester) async {
      await pump(tester, const Size(390, 844));
      picker.result = FakeImagePicker.write('pick.jpg', [
        0xFF,
        0xD8,
        0xFF,
        0xE0,
      ]);
      await openSheet(tester);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(picker.sources, [source]);
      expect(vm().pendingPhoto.value, isNotNull);
      expect(profiles.uploads, isEmpty, reason: 'upload waits for Save');
      await closeSnackbars(tester);
    });
  }

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await pump(tester, const Size(390, 844));
    picker.result = null;
    await vm().choosePhoto(ImageSource.gallery);
    expect(vm().pendingPhoto.value, isNull);
    await closeSnackbars(tester);
  });

  for (final (code, title) in [
    ('camera_access_denied', 'Camera access is off'),
    ('photo_access_denied', 'Photo access is off'),
    ('no_available_camera', 'No camera available'),
  ]) {
    testWidgets('$code is explained to the user', (tester) async {
      await pump(tester, const Size(390, 844));
      picker.error = PlatformException(code: code);
      await vm().choosePhoto(ImageSource.camera);
      await tester.pump();
      expect(find.text(title), findsOneWidget);
      expect(vm().pendingPhoto.value, isNull);
      await closeSnackbars(tester);
    });
  }

  testWidgets('a non-image file is rejected before upload', (tester) async {
    await pump(tester, const Size(390, 844));
    picker.result = FakeImagePicker.write('fake.jpg', '%PDF-1.7'.codeUnits);
    await vm().choosePhoto(ImageSource.gallery);
    await tester.pump();
    expect(vm().pendingPhoto.value, isNull);
    expect(find.text("Couldn't use that photo"), findsOneWidget);
    await closeSnackbars(tester);
  });

  testWidgets('an upload failure keeps the saved photo and allows retry', (
    tester,
  ) async {
    profiles.put(
      'uid-1',
      const UserProfile(
        id: UserProfile.selfId,
        type: ProfileType.self,
        fullName: 'Eleanor Vance',
        photoUrl: 'https://old/photo.jpg',
        photoPath: 'users/uid-1/profiles/self/old.jpg',
      ),
    );
    await pump(tester, const Size(390, 844));
    vm().pendingPhoto.value = File(
      FakeImagePicker.write('new.jpg', [0xFF, 0xD8, 0xFF]).path,
    );
    profiles.uploadFailure = const ProfileFailure(
      'Could not upload your photo.',
    );
    await vm().saveAndContinue();
    await tester.pump();
    expect(
      Get.find<AuthService>().profiles.selfProfile!.photoUrl,
      'https://old/photo.jpg',
    );
    expect(profiles.deleted, isEmpty, reason: 'old photo kept');
    expect(vm().pendingPhoto.value, isNotNull, reason: 'retry possible');
    expect(vm().uploadProgress.value, isNull);

    profiles.uploadFailure = null;
    await vm().saveAndContinue();
    await tester.pumpAndSettle();
    expect(
      profiles.profilesOf('uid-1')[UserProfile.selfId]!.photoPath,
      'users/uid-1/profiles/self/avatar_1.jpg',
    );
    expect(profiles.deleted, ['users/uid-1/profiles/self/old.jpg']);
    await closeSnackbars(tester);
  });

  group('managed profiles', () {
    const self = UserProfile(
      id: UserProfile.selfId,
      type: ProfileType.self,
      fullName: 'Eleanor Vance',
      emergencyContactName: 'Self Contact',
    );
    const parent = UserProfile(
      id: 'p1',
      type: ProfileType.parent,
      fullName: 'Ruth Vance',
      relationship: 'Mother / Senior Parent',
    );

    testWidgets(
      'editing a profile saves only that profile, even after switching',
      (tester) async {
        profiles
          ..put('uid-1', self)
          ..put('uid-1', parent);
        await pump(
          tester,
          const Size(390, 844),
          args: const ProfileEditorArgs.edit('p1'),
        );
        expect(vm().nameController.text, 'Ruth Vance');
        expect(
          vm().contactNameController.text,
          '',
          reason: "Myself's data must not leak in",
        );

        // Switching the active profile elsewhere must not redirect this save.
        await Get.find<AuthService>().profiles.switchTo(UserProfile.selfId);
        vm().nameController.text = 'Ruth A. Vance';
        await vm().saveAndContinue();
        await tester.pumpAndSettle();
        expect(profiles.profilesOf('uid-1')['p1']!.fullName, 'Ruth A. Vance');
        expect(profiles.profilesOf('uid-1')[UserProfile.selfId], self);
        await closeSnackbars(tester);
      },
    );

    testWidgets('the owner choice is locked when editing', (tester) async {
      profiles.put('uid-1', parent);
      await pump(
        tester,
        const Size(390, 844),
        args: const ProfileEditorArgs.edit('p1'),
      );
      vm().selectProfileFor(AccountFor.myself);
      expect(vm().profileFor.value, AccountFor.caregiver);
      expect(vm().targetId, 'p1');
      await closeSnackbars(tester);
    });

    testWidgets('adding a Spouse creates a new profile with its own id', (
      tester,
    ) async {
      profiles
        ..put('uid-1', self)
        ..put('uid-1', parent);
      await pump(
        tester,
        const Size(390, 844),
        args: const ProfileEditorArgs.create(ProfileType.spouse),
      );
      expect(vm().nameController.text, isEmpty);
      expect(vm().relationship.value, 'Spouse or Partner');
      vm().nameController.text = 'Sam Vance';
      await vm().saveAndContinue();
      await tester.pumpAndSettle();
      final created = profiles
          .profilesOf('uid-1')
          .values
          .where((p) => p.type == ProfileType.spouse);
      expect(created.single.fullName, 'Sam Vance');
      expect(created.single.id, isNot(anyOf(UserProfile.selfId, 'p1')));
      expect(profiles.profilesOf('uid-1'), hasLength(3));
      await closeSnackbars(tester);
    });

    testWidgets('retrying a failed create updates the same new profile', (
      tester,
    ) async {
      await pump(
        tester,
        const Size(390, 844),
        args: const ProfileEditorArgs.create(ProfileType.other),
      );
      vm().nameController.text = 'Pat';
      profiles.saveFailure = const ProfileFailure('offline');
      await vm().saveAndContinue();
      profiles.saveFailure = null;
      await vm().saveAndContinue();
      await tester.pumpAndSettle();
      expect(
        profiles.profilesOf('uid-1').values.where((p) => p.fullName == 'Pat'),
        hasLength(1),
      );
      await closeSnackbars(tester);
    });

    testWidgets("setup never carries one profile's values into another", (
      tester,
    ) async {
      profiles.put('uid-1', self);
      await pump(tester, const Size(390, 844));
      expect(vm().contactNameController.text, 'Self Contact');
      vm().selectProfileFor(AccountFor.caregiver);
      expect(vm().nameController.text, isEmpty);
      expect(vm().contactNameController.text, isEmpty);
      vm().selectProfileFor(AccountFor.myself);
      expect(vm().contactNameController.text, 'Self Contact');
      await closeSnackbars(tester);
    });

    testWidgets('editing a profile that no longer exists shows an error', (
      tester,
    ) async {
      profiles.put('uid-1', self);
      await pump(
        tester,
        const Size(390, 844),
        args: const ProfileEditorArgs.edit('gone'),
      );
      expect(find.text('This profile is no longer available.'), findsOneWidget);
      await vm().saveAndContinue();
      expect(profiles.profilesOf('uid-1').keys, [UserProfile.selfId]);
      await closeSnackbars(tester);
    });
  });
}
