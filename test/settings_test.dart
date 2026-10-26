import 'dart:ui' as ui;

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/core/config/app_config.dart';
import 'package:dosemate/data/repositories/account_repository.dart';
import 'package:dosemate/modules/delete_account/view_model/delete_account_view_model.dart';
import 'package:dosemate/modules/delete_account/views/delete_account_view.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/calendar_service.dart';
import 'package:dosemate/data/services/history_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/family/bindings/family_binding.dart';
import 'package:dosemate/modules/family/view_model/family_view_model.dart';
import 'package:dosemate/modules/family/views/family_view.dart';
import 'package:dosemate/modules/history/view_model/history_view_model.dart';
import 'package:dosemate/modules/notifications/bindings/notifications_binding.dart';
import 'package:dosemate/modules/notifications/view_model/notifications_view_model.dart';
import 'package:dosemate/modules/notifications/views/notifications_view.dart';
import 'package:dosemate/modules/profile_setup/view_model/profile_setup_view_model.dart';
import 'package:dosemate/modules/profile_setup/views/profile_setup_view.dart';
import 'package:dosemate/modules/settings/view_model/settings_view_model.dart';
import 'package:dosemate/modules/settings/views/settings_view.dart';
import 'package:dosemate/modules/shell/bindings/shell_binding.dart';
import 'package:dosemate/modules/shell/view_model/shell_view_model.dart';
import 'package:dosemate/modules/shell/views/main_shell_view.dart';
import 'package:dosemate/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_care.dart';
import 'support/fake_image_picker.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

void main() {
  const uid = 'uid-1';
  late FakeProfiles store;
  late ProfileService profiles;
  late AuthService auth;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
    auth = Get.put(AuthService(AuthRepository(NoAuth()), profiles));
    auth.user.value = FakeUser();
    final careStore = FakeCare();
    seedCare(careStore);
    final care = putCare(profiles, careStore, now: fixedNow);
    Get.put(CalendarService(care, debounce: Duration.zero));
    Get.put(HistoryService(care, pageSize: 5));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(Get.reset);

  /// The app's real routes for the shell, Family, Notifications and the
  /// profile editor.
  Future<void> open(
    WidgetTester tester, {
    String route = AppRoutes.settings,
    Size size = const Size(400, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: route,
        getPages: [
          for (final (name, tab) in [
            (AppRoutes.home, 0),
            (AppRoutes.history, 3),
            (AppRoutes.settings, 4),
          ])
            GetPage(
              name: name,
              page: () => const MainShellView(),
              binding: ShellBinding(initialTab: tab),
              transition: Transition.noTransition,
            ),
          GetPage(
            name: AppRoutes.family,
            page: () => const FamilyView(),
            binding: FamilyBinding(),
          ),
          GetPage(
            name: AppRoutes.notifications,
            page: () => const NotificationsView(),
            binding: NotificationsBinding(),
          ),
          GetPage(
            name: AppRoutes.deleteAccount,
            page: () => const DeleteAccountView(),
            binding: BindingsBuilder(
              () => Get.lazyPut(
                () => DeleteAccountViewModel(
                  accounts: AccountRepository(NoFirestore()),
                ),
              ),
            ),
          ),
          GetPage(
            name: AppRoutes.profileSetup,
            page: () => const ProfileSetupView(),
            binding: BindingsBuilder(
              () => Get.lazyPut(
                () => ProfileSetupViewModel(picker: FakeImagePicker()),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byKey(ValueKey('settings-$key'));

  /// Scrolls Settings until [finder] is built and on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
  }

  bool settingsSelected(WidgetTester tester) =>
      tester
          .getSemantics(
            find.descendant(
              of: find.byType(AppBottomNav),
              matching: find.bySemanticsLabel('Settings'),
            ),
          )
          .flagsCollection
          .isSelected ==
      ui.Tristate.isTrue;

  /// GetX snackbars animate on timers; close them before the test ends.
  Future<void> closeSnackbars(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      Get.closeAllSnackbars();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('Settings replaces Family in the tab bar, in the same shell', (
    tester,
  ) async {
    await open(tester, route: AppRoutes.home);
    final nav = find.byType(AppBottomNav);
    expect(
      find.descendant(of: nav, matching: find.text('Family')),
      findsNothing,
    );
    final routeBefore = Get.currentRoute;
    await tester.tap(find.descendant(of: nav, matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(Get.find<ShellViewModel>().index.value, 4);
    expect(settingsSelected(tester), isTrue);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(Get.currentRoute, routeBefore); // switched in place
    // Its entries moved here from the top bar.
    expect(find.byTooltip('Notifications'), findsNothing);
  });

  testWidgets('shows the account holder, apart from the active profile', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('ACCOUNT HOLDER'), findsOneWidget);
    expect(find.text('Eleanor Vance'), findsWidgets);
    expect(find.text('eleanor@example.com'), findsOneWidget);
    expect(find.text('Family & Profiles'), findsOneWidget);
    await reveal(tester, find.text('Log out'));
    expect(find.text('Log out'), findsOneWidget);
    await tester.drag(
      find
          .descendant(
            of: find.byType(SettingsView),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();

    await profiles.switchTo('p1');
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('ACCOUNT HOLDER'),
      matching: find.byType(DmCard),
    );
    // The account stays Eleanor; Ruth shows as the profile being managed.
    expect(
      find.descendant(of: card, matching: find.text('Eleanor Vance')),
      findsOneWidget,
    );
    expect(find.text('Now managing Ruth Vance'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppTopBar),
        matching: find.text('Ruth Vance'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Edit profile edits the account holder and returns here', (
    tester,
  ) async {
    await profiles.switchTo('p1');
    await open(tester);
    await tap(tester, row('edit-profile'));
    final editor = Get.find<ProfileSetupViewModel>();
    expect(editor.mode, EditorMode.edit);
    // Myself, not the active family profile.
    expect(editor.targetId, UserProfile.selfId);
    expect(editor.nameController.text, 'Eleanor Vance');

    editor.nameController.text = 'Eleanor M. Vance';
    await editor.saveAndContinue();
    await tester.pumpAndSettle();
    expect(
      store.profilesOf(uid)[UserProfile.selfId]!.fullName,
      'Eleanor M. Vance',
    );
    expect(find.byType(ProfileSetupView), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(Get.find<ShellViewModel>().index.value, 4);
    expect(find.text('Eleanor M. Vance'), findsOneWidget);
    await closeSnackbars(tester);
  });

  testWidgets('Family & Profiles opens the Family screen; back returns', (
    tester,
  ) async {
    await open(tester);
    final shell = Get.find<ShellViewModel>();
    final settings = Get.find<SettingsViewModel>();
    for (var i = 0; i < 2; i++) {
      await tap(tester, row('family'));
      expect(find.byType(FamilyView), findsOneWidget);
      expect(find.text('Family & Profiles'), findsOneWidget); // its back bar
      expect(find.text('Your Profiles'), findsOneWidget);

      // Switching there is the same switch the whole app uses.
      if (i == 0) {
        await tester.ensureVisible(find.text('Switch to Ruth'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch to Ruth'));
        await tester.pumpAndSettle();
        expect(profiles.activeProfileId.value, 'p1');
      }

      await back(tester);
      expect(find.byType(FamilyView), findsNothing);
      expect(find.byType(SettingsView), findsOneWidget);
      expect(settingsSelected(tester), isTrue);
      // One shell and Settings controller throughout; Family's is released
      // with its screen, so reopening never stacks a second one.
      expect(identical(Get.find<ShellViewModel>(), shell), isTrue);
      expect(identical(Get.find<SettingsViewModel>(), settings), isTrue);
      expect(Get.isRegistered<FamilyViewModel>(), isFalse);
    }
    expect(find.text('Now managing Ruth Vance'), findsOneWidget);
  });

  testWidgets('Notifications opens the Notifications screen; back returns', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, row('notifications'));
    expect(find.byType(NotificationsView), findsOneWidget);
    expect(find.text('Notifications & Alerts'), findsOneWidget);
    await back(tester);
    expect(find.byType(NotificationsView), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(settingsSelected(tester), isTrue);
    expect(Get.isRegistered<NotificationsViewModel>(), isFalse);
  });

  testWidgets('other tabs keep their state across Settings screens', (
    tester,
  ) async {
    await open(tester, route: AppRoutes.history);
    final historyVm = Get.find<HistoryViewModel>();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tap(tester, row('family'));
    await back(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(identical(Get.find<HistoryViewModel>(), historyVm), isTrue);
    expect(find.text('Log History & Reports'), findsOneWidget);
  });

  testWidgets('Privacy Policy links to the hosted policy; Delete Account '
      'opens its screen and back returns', (tester) async {
    await open(tester);
    await reveal(tester, row('privacy'));
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(
      AppConfig.privacyPolicyUrl.toString(),
      'https://dosemate-70150.web.app/privacy/',
    );
    await tap(tester, row('delete-account'));
    expect(find.byType(DeleteAccountView), findsOneWidget);
    expect(find.text('What’s permanently deleted'), findsOneWidget);
    await back(tester);
    expect(find.byType(DeleteAccountView), findsNothing);
    expect(row('delete-account'), findsOneWidget);
  });

  testWidgets('Log out asks first, then signs out', (tester) async {
    var signOuts = 0;
    // Counts sign outs (the fake Firebase then fails, which is reported).
    auth.beforeSignOut.add(() async => signOuts++);
    await open(tester);
    await tap(tester, row('logout'));
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(signOuts, 0);

    await tap(tester, row('logout'));
    await tester.tap(find.widgetWithText(TextButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
    await closeSnackbars(tester);
  });

  for (final (size, scale) in const [
    (Size(320, 568), 1.0),
    (Size(320, 640), 2.0),
    (Size(390, 844), 1.5),
  ]) {
    testWidgets('fits ${size.width}x${size.height} at ${scale}x text, '
        'with safe areas', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      await open(tester, size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      for (final key in ['edit-profile', 'family', 'notifications', 'logout']) {
        // The list builds lazily: scroll each row into view.
        await tester.scrollUntilVisible(
          row(key),
          120,
          scrollable: find
              .descendant(
                of: find.byType(SettingsView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(row(key));
        expect(rect.height, greaterThanOrEqualTo(48), reason: key);
        expect(tester.takeException(), isNull, reason: key);
      }
      // Below the status bar.
      expect(tester.getRect(find.byType(AppTopBar)).top, 0);
      expect(
        tester.getTopLeft(find.text('Settings').first).dy,
        greaterThanOrEqualTo(44),
      );
    });
  }
}
