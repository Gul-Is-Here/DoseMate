import 'package:dosemate/app/middlewares/auth_middleware.dart';
import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/signup/view_model/signup_view_model.dart';
import 'package:dosemate/modules/verify_email/view_model/verify_email_view_model.dart';
import 'package:dosemate/modules/verify_email/views/verify_email_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_test.dart' show FakeAuth, FakeUser, FakePicker;
import 'support/fake_profiles.dart';

void main() {
  late FakeAuth firebase;
  late AuthService auth;
  late FakeProfiles store;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() async {
    Get.testMode = true;
    firebase = FakeAuth();
    store = FakeProfiles();
    auth = await Get.put(
      AuthService(
        AuthRepository(firebase, googlePicker: FakePicker()),
        ProfileService(store),
      ),
    ).init();
  });

  tearDown(Get.reset);

  Widget page(String name) => Scaffold(body: Text('page:$name'));

  /// The app's routes and guards, with stand-in screens except Verify Email.
  Future<void> pumpApp(WidgetTester tester, String initial) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: initial,
        getPages: [
          GetPage(name: AppRoutes.login, page: () => page('login')),
          GetPage(name: AppRoutes.signup, page: () => page('signup')),
          GetPage(
            name: AppRoutes.verifyEmail,
            page: () => const VerifyEmailView(),
            binding: BindingsBuilder.put(() => VerifyEmailViewModel()),
            middlewares: [SignedInMiddleware()],
          ),
          GetPage(
            name: AppRoutes.profileSetup,
            page: () => page('setup'),
            middlewares: [VerifiedMiddleware()],
          ),
          GetPage(
            name: AppRoutes.home,
            page: () => page('home'),
            middlewares: [VerifiedMiddleware()],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> signUp(WidgetTester tester, {FakeUser? user}) async {
    if (user != null) firebase.nextUser = user;
    final vm = Get.put(SignupViewModel());
    vm.nameController.text = 'Eleanor Vance';
    vm.emailController.text = 'a@b.co';
    vm.passwordController.text = 'letters123';
    vm.confirmPasswordController.text = 'letters123';
    await vm.createAccount();
    await tester.pumpAndSettle();
  }

  testWidgets('sign up sends the email and shows Verify Email, not setup', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.signup);
    final user = FakeUser(emailVerified: false, provider: 'password');
    await signUp(tester, user: user);
    expect(user.verificationEmails, 1);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(
      find.textContaining('We sent a verification link to a@b.co'),
      findsOne,
    );
    expect(find.text("I've Verified My Email"), findsOneWidget);
    expect(find.text('Resend email in 60s'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('page:setup'), findsNothing);
    // Nothing loads for an unverified account.
    expect(store.migrations, isEmpty);
    await flush(tester);
  });

  testWidgets('a failed first send says so and allows Resend at once', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.signup);
    await signUp(
      tester,
      user: FakeUser(emailVerified: false, provider: 'password')
        ..sendError = FirebaseAuthException(code: 'network-request-failed'),
    );
    expect(find.textContaining('We couldn’t send'), findsOneWidget);
    expect(find.text("Couldn't send the verification email"), findsOneWidget);
    expect(find.text('Email sent'), findsNothing);
    expect(find.text('Resend Email'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('resend: success starts the cooldown; a rate limit shows an '
      'error, never "Email sent"', (tester) async {
    final user = FakeUser(emailVerified: false, provider: 'password');
    firebase.signedIn = user;
    auth.user.value = user;
    await pumpApp(tester, AppRoutes.verifyEmail);
    expect(find.text('Resend Email'), findsOneWidget);

    user.sendError = FirebaseAuthException(code: 'too-many-requests');
    await tester.tap(find.text('Resend Email'));
    await tester.pump();
    expect(find.text("Couldn't send email"), findsOneWidget);
    expect(find.text('Email sent'), findsNothing);
    expect(find.text('Resend email in 60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();

    user.sendError = null;
    await tester.tap(find.text('Resend Email'));
    await tester.pump();
    expect(user.verificationEmails, 1);
    expect(find.text('Email sent'), findsOneWidget);
    expect(find.text('Resend email in 60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
  });

  testWidgets('unverified users are redirected away from Home and setup', (
    tester,
  ) async {
    final user = FakeUser(emailVerified: false, provider: 'password');
    firebase.signedIn = user;
    auth.user.value = user;
    await pumpApp(tester, AppRoutes.home);
    expect(find.text('Verify your email'), findsOneWidget);
    Get.toNamed(AppRoutes.profileSetup);
    await tester.pumpAndSettle();
    expect(find.text('page:setup'), findsNothing);
    expect(find.text('Verify your email'), findsWidgets);
  });

  testWidgets('not verified yet stays put; verified moves on to setup', (
    tester,
  ) async {
    final user = FakeUser(emailVerified: false, provider: 'password');
    firebase.signedIn = user;
    auth.user.value = user;
    await pumpApp(tester, AppRoutes.verifyEmail);
    await tester.tap(find.text("I've Verified My Email"));
    await tester.pumpAndSettle();
    expect(find.text('Not verified yet'), findsOneWidget);
    expect(find.text('Verify your email'), findsOneWidget);
    await flush(tester);

    // The user opens the link, then returns to the app.
    user.emailVerified = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(user.tokenRefreshes, 1);
    expect(find.text('page:setup'), findsOneWidget);
  });

  testWidgets('a verified user with a completed profile goes Home', (
    tester,
  ) async {
    store
      ..put(
        'uid-1',
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Eleanor Vance',
        ),
      )
      ..completeSetup('uid-1');
    final user = FakeUser(emailVerified: false, provider: 'password');
    firebase.signedIn = user;
    auth.user.value = user;
    await pumpApp(tester, AppRoutes.verifyEmail);
    user.emailVerified = true;
    await tester.tap(find.text("I've Verified My Email"));
    await tester.pumpAndSettle();
    expect(find.text('page:home'), findsOneWidget);
  });
}
