import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/account_repository.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/delete_account/bindings/delete_account_binding.dart';
import 'package:dosemate/modules/delete_account/view_model/delete_account_view_model.dart';
import 'package:dosemate/modules/delete_account/views/delete_account_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

/// Records reauthentication and sign out; never touches Firebase.
class FakeAuthRepo extends AuthRepository {
  FakeAuthRepo({this.password = true}) : super(NoAuth());

  final bool password;
  final reauths = <String>[];
  Object? nextError;
  bool? signedOutRevokingGoogle;

  @override
  bool get hasPassword => password;

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    reauths.add('password:$password');
    if (nextError case final e?) {
      nextError = null;
      throw e;
    }
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    reauths.add('google');
    if (nextError case final e?) {
      nextError = null;
      throw e;
    }
  }

  /// As in the app, where the auth stream reports it: sign in opens.
  @override
  Future<void> signOut({bool revokeGoogle = false}) async {
    signedOutRevokingGoogle = revokeGoogle;
    Get.offAllNamed(AppRoutes.login);
  }
}

/// The server call, scripted: [failures] are thrown in turn, then success.
class FakeAccounts extends AccountRepository {
  FakeAccounts(this.profiles) : super(NoFirestore());

  final ProfileService profiles;
  final failures = <AccountDeletionFailure>[];
  final calls = <String>[];

  /// Whether profiles (and everything following them) were stopped while
  /// the server deleted.
  final syncDuringDelete = <bool>[];

  @override
  Future<void> flushPendingWrites() async => calls.add('flush');

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    syncDuringDelete.add(profiles.uid != null);
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }
}

void main() {
  const uid = 'uid-1';
  late ProfileService profiles;
  late FakeAuthRepo repo;
  late AuthService auth;
  late FakeAccounts accounts;
  late List<String> cleanup;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  Future<void> setUpWith({bool password = true}) async {
    Get.testMode = true;
    final store = FakeProfiles()
      ..put(
        uid,
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Eleanor Vance',
        ),
      );
    profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    repo = FakeAuthRepo(password: password);
    auth = Get.put(AuthService(repo, profiles));
    auth.user.value = FakeUser();
    cleanup = [];
    auth.beforeSignOut.add(() async => cleanup.add('alarms+push'));
    auth.afterAccountDeleted.add((id) async => cleanup.add('local:$id'));
    accounts = FakeAccounts(profiles);
    Get.put<AccountRepository>(accounts);
  }

  tearDown(Get.reset);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoutes.deleteAccount,
        getPages: [
          GetPage(
            name: AppRoutes.deleteAccount,
            page: () => const DeleteAccountView(),
            binding: DeleteAccountBinding(),
          ),
          GetPage(
            name: AppRoutes.login,
            page: () => const Scaffold(body: Text('Sign in screen')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  final button = find.byKey(const ValueKey('delete-account-confirm'));
  final passwordField = find.byKey(const ValueKey('delete-account-password'));
  final understood = find.byKey(const ValueKey('delete-account-understood'));

  bool enabled(WidgetTester tester) =>
      Get.find<DeleteAccountViewModel>().canSubmit;

  Future<void> confirm(WidgetTester tester, {String? password}) async {
    if (password != null) await tester.enterText(passwordField, password);
    await tester.ensureVisible(understood);
    await tester.pumpAndSettle();
    await tester.tap(understood);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('says what is deleted; needs the password and the checkbox', (
    tester,
  ) async {
    await setUpWith();
    await open(tester);
    expect(find.text('What’s permanently deleted'), findsOneWidget);
    expect(find.textContaining('eleanor@example.com'), findsOneWidget);
    expect(find.textContaining('medicines, schedules, dose history'), findsOne);
    expect(find.textContaining('Their profiles and data stay'), findsOne);
    expect(enabled(tester), isFalse);
    await tester.enterText(passwordField, 'secret');
    await tester.pump();
    expect(enabled(tester), isFalse); // not yet confirmed
    await confirm(tester);
    expect(enabled(tester), isTrue);
    expect(accounts.calls, isEmpty);
  });

  testWidgets('deletes: confirms it’s you, syncs, pauses data, then clears '
      'this device and signs out', (tester) async {
    await setUpWith();
    await open(tester);
    await confirm(tester, password: 'secret');
    await submit(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(repo.reauths, ['password:secret']);
    expect(accounts.calls, ['flush', 'delete']);
    // Nothing on this device could write the data back meanwhile.
    expect(accounts.syncDuringDelete, [false]);
    expect(cleanup, ['alarms+push', 'local:$uid']);
    expect(repo.signedOutRevokingGoogle, isTrue);
    expect(profiles.uid, isNull);
    expect(find.text('Account deleted'), findsOneWidget);
    await tester.pumpAndSettle();
    // Back at authentication; the deletion screen is gone.
    expect(find.text('Sign in screen'), findsOneWidget);
    expect(find.byType(DeleteAccountView), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a wrong password stops before anything is deleted', (
    tester,
  ) async {
    await setUpWith();
    await open(tester);
    repo.nextError = const AuthFailure(
      'That password isn’t right. Try again.',
      code: 'invalid-credential',
    );
    await confirm(tester, password: 'nope');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('That password isn’t right. Try again.'), findsOneWidget);
    expect(accounts.calls, isEmpty);
    expect(profiles.uid, uid);
    expect(cleanup, isEmpty);
  });

  testWidgets('a partial failure is shown as such and retried; success only '
      'once the server finishes', (tester) async {
    await setUpWith();
    await open(tester);
    accounts.failures.add(
      const AccountDeletionFailure(
        DeletionProblem.incomplete,
        'Your account wasn’t fully deleted. Some of your data may already be '
        'removed. Try again to finish.',
      ),
    );
    await confirm(tester, password: 'secret');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Not fully deleted'), findsOneWidget);
    expect(find.textContaining('Try again to finish'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Account deleted'), findsNothing);
    expect(cleanup, isEmpty);
    expect(repo.signedOutRevokingGoogle, isNull);
    // Kept paused: the account is half gone, so nothing is recreated.
    expect(profiles.uid, isNull);

    await submit(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(accounts.calls, ['flush', 'delete', 'flush', 'delete']);
    expect(repo.reauths, hasLength(2));
    expect(find.text('Account deleted'), findsOneWidget);
    expect(repo.signedOutRevokingGoogle, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a stale sign in asks again and restores the account’s data', (
    tester,
  ) async {
    await setUpWith();
    await open(tester);
    accounts.failures.add(
      const AccountDeletionFailure(
        DeletionProblem.recentLogin,
        'For your security, confirm it’s you again. Nothing was deleted.',
      ),
    );
    await confirm(tester, password: 'secret');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Account not deleted'), findsOneWidget);
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    expect(Get.find<DeleteAccountViewModel>().password.text, isEmpty);
    expect(profiles.uid, uid); // sync resumed
    expect(cleanup, isEmpty);
  });

  testWidgets('Google accounts confirm with Google; cancelling does nothing', (
    tester,
  ) async {
    await setUpWith(password: false);
    await open(tester);
    expect(passwordField, findsNothing);
    expect(find.textContaining('confirm with the Google account'), findsOne);
    await confirm(tester);
    repo.nextError = const AuthCancelled();
    await submit(tester);
    await tester.pumpAndSettle();
    expect(repo.reauths, ['google']);
    expect(accounts.calls, isEmpty);
    expect(Get.find<DeleteAccountViewModel>().error.value, isNull);

    await submit(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(repo.reauths, ['google', 'google']);
    expect(accounts.calls, ['flush', 'delete']);
    expect(repo.signedOutRevokingGoogle, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an account already gone on the server is only cleared here', (
    tester,
  ) async {
    await setUpWith();
    await open(tester);
    repo.nextError = const AuthFailure('gone', code: 'user-not-found');
    await confirm(tester, password: 'secret');
    await submit(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(accounts.calls, isEmpty);
    expect(cleanup, ['alarms+push', 'local:$uid']);
    expect(repo.signedOutRevokingGoogle, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('server errors map to what the screen offers next', () {
    DeletionProblem p(String code, [Object? details]) =>
        AccountRepository.failureFor(code, details, null).problem;
    expect(
      p('failed-precondition', {'reason': 'requires-recent-login'}),
      DeletionProblem.recentLogin,
    );
    expect(p('aborted', {'reason': 'in-progress'}), DeletionProblem.inProgress);
    expect(
      p('internal', {'reason': 'incomplete', 'step': 'files'}),
      DeletionProblem.incomplete,
    );
    expect(p('unavailable'), DeletionProblem.network);
    expect(p('deadline-exceeded'), DeletionProblem.timeout);
    expect(p('internal'), DeletionProblem.unknown);
  });
}
