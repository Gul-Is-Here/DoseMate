import 'dart:async';

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/core/utils/validators.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/google_account_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_profiles.dart';

class FakeUserInfo implements UserInfo {
  FakeUserInfo(this.providerId);

  @override
  final String providerId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser({required this.emailVerified, required String provider})
    : providerData = [FakeUserInfo(provider)];

  @override
  String get uid => 'uid-1';

  @override
  bool emailVerified;

  @override
  final List<UserInfo> providerData;

  String? name;
  int verificationEmails = 0;

  @override
  String? get email => 'a@b.co';

  @override
  String? get displayName => name;

  @override
  Future<void> updateDisplayName(String? displayName) async =>
      name = displayName;

  /// Thrown by the next verification send, e.g. a rate limit.
  FirebaseAuthException? sendError;
  int tokenRefreshes = 0;

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    if (sendError case final e?) throw e;
    verificationEmails++;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) tokenRefreshes++;
    return 'token';
  }

  @override
  Future<void> reload() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCredential implements UserCredential {
  FakeCredential(this.user);

  @override
  final User? user;

  @override
  AdditionalUserInfo? get additionalUserInfo => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePicker implements GoogleAccountPicker {
  Exception? nextError;
  int signOuts = 0;

  @override
  bool get isSupported => true;

  @override
  Future<String> idToken() async {
    if (nextError case final e?) throw e;
    return 'id-token';
  }

  @override
  Future<void> signOut() async => signOuts++;

  int disconnects = 0;

  @override
  Future<void> disconnect() async => disconnects++;
}

class FakeAuth implements FirebaseAuth {
  final controller = StreamController<User?>.broadcast();
  User? signedIn;
  FirebaseAuthException? nextError;
  final resetEmails = <String>[];

  @override
  User? get currentUser => signedIn;

  @override
  Stream<User?> authStateChanges() async* {
    yield signedIn;
    yield* controller.stream;
  }

  Future<UserCredential> _complete(User user) async {
    if (nextError case final error?) throw error;
    signedIn = user;
    controller.add(user); // as Firebase reports sign ins
    return FakeCredential(user);
  }

  /// The user the next sign up creates.
  FakeUser? nextUser;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => _complete(
    nextUser ?? FakeUser(emailVerified: false, provider: 'password'),
  );

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _complete(FakeUser(emailVerified: true, provider: 'password'));

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) =>
      _complete(FakeUser(emailVerified: true, provider: 'google.com'));

  final credentials = <AuthCredential>[];

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) {
    credentials.add(credential);
    return _complete(FakeUser(emailVerified: true, provider: 'google.com'));
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (nextError case final error?) throw error;
    resetEmails.add(email);
  }

  @override
  Future<void> signOut() async {
    signedIn = null;
    controller.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAuth auth;
  late AuthRepository repo;
  late FakeProfiles profiles;
  late FakePicker picker;

  setUp(() {
    auth = FakeAuth();
    picker = FakePicker();
    repo = AuthRepository(auth, googlePicker: picker);
    profiles = FakeProfiles();
  });

  group('AuthRepository', () {
    test('sign up sets the name and sends a verification email', () async {
      await repo.signUpWithEmail(
        name: 'Eleanor',
        email: 'a@b.co',
        password: 'abc12345',
      );
      final user = auth.signedIn! as FakeUser;
      expect(user.name, 'Eleanor');
      expect(user.verificationEmails, 1);
      expect(AuthRepository.needsEmailVerification(user), isTrue);
    });

    test('a failed verification send still creates the account', () async {
      auth.nextUser = FakeUser(emailVerified: false, provider: 'password')
        ..sendError = FirebaseAuthException(code: 'too-many-requests');
      final sent = await repo.signUpWithEmail(
        name: 'Eleanor',
        email: 'a@b.co',
        password: 'abc12345',
      );
      expect(sent, isFalse);
      expect(auth.signedIn, isNotNull);
    });

    test('resend errors keep their code; nothing is sent', () async {
      final user = FakeUser(emailVerified: false, provider: 'password')
        ..sendError = FirebaseAuthException(code: 'too-many-requests');
      auth.signedIn = user;
      await expectLater(
        repo.sendEmailVerification(),
        throwsA(
          isA<AuthFailure>().having((f) => f.code, 'code', 'too-many-requests'),
        ),
      );
      expect(user.verificationEmails, 0);
    });

    test('verification refreshes the ID token only once verified', () async {
      final user = FakeUser(emailVerified: false, provider: 'password');
      auth.signedIn = user;
      expect(await repo.reloadEmailVerified(), isFalse);
      expect(user.tokenRefreshes, 0);
      user.emailVerified = true;
      expect(await repo.reloadEmailVerified(), isTrue);
      expect(user.tokenRefreshes, 1);
    });

    test('invalid credentials map to one generic message', () async {
      for (final code in [
        'invalid-credential',
        'wrong-password',
        'user-not-found',
      ]) {
        auth.nextError = FirebaseAuthException(code: code);
        await expectLater(
          repo.signInWithEmail(email: 'a@b.co', password: 'x'),
          throwsA(
            isA<AuthFailure>().having(
              (f) => f.message,
              'message',
              'Incorrect email or password.',
            ),
          ),
        );
      }
    });

    test(
      'duplicate email and provider conflicts are rejected, not merged',
      () async {
        auth.nextError = FirebaseAuthException(code: 'email-already-in-use');
        await expectLater(
          repo.signUpWithEmail(
            name: 'n',
            email: 'a@b.co',
            password: 'abc12345',
          ),
          throwsA(isA<AuthFailure>()),
        );
        auth.nextError = FirebaseAuthException(
          code: 'account-exists-with-different-credential',
        );
        await expectLater(repo.signInWithGoogle(), throwsA(isA<AuthFailure>()));
        expect(auth.signedIn, isNull);
      },
    );

    test(
      'Google sign in uses the native picker token, not a browser',
      () async {
        expect(await repo.signInWithGoogle(), isFalse);
        expect(auth.credentials.single.providerId, 'google.com');
        expect(AuthRepository.needsEmailVerification(auth.signedIn!), isFalse);
      },
    );

    test('closing the Google picker is a cancellation, not an error', () async {
      picker.nextError = const GooglePickerCancelled();
      await expectLater(repo.signInWithGoogle(), throwsA(isA<AuthCancelled>()));
      expect(auth.signedIn, isNull);
    });

    test('picker failures show a readable message', () async {
      picker.nextError = const GooglePickerFailure('unknownError');
      await expectLater(repo.signInWithGoogle(), throwsA(isA<AuthFailure>()));
    });

    test('sign out also forgets the Google account', () async {
      await repo.signInWithGoogle();
      await repo.signOut();
      expect(auth.signedIn, isNull);
      expect(picker.signOuts, 1);
    });

    test('password reset does not reveal whether the account exists', () async {
      await repo.sendPasswordReset('a@b.co');
      expect(auth.resetEmails, ['a@b.co']);
      auth.nextError = FirebaseAuthException(code: 'user-not-found');
      await expectLater(repo.sendPasswordReset('nobody@b.co'), completes);
    });
  });

  group('AuthService', () {
    test('signed-out start routes to onboarding', () async {
      final service = await AuthService(repo, ProfileService(profiles)).init();
      expect(service.initialRoute, AppRoutes.onboarding);
    });

    test('restored verified session routes to home', () async {
      auth.signedIn = FakeUser(emailVerified: true, provider: 'password');
      final service = await AuthService(repo, ProfileService(profiles)).init();
      expect(service.initialRoute, AppRoutes.home);
    });

    test('restored unverified email session routes to verification, and '
        'loads no data', () async {
      auth.signedIn = FakeUser(emailVerified: false, provider: 'password');
      final service = await AuthService(repo, ProfileService(profiles)).init();
      expect(service.initialRoute, AppRoutes.verifyEmail);
      expect(service.needsVerification, isTrue);
      expect(profiles.migrations, isEmpty);
    });

    test('verification picks up after reload', () async {
      final user = FakeUser(emailVerified: false, provider: 'password');
      auth.signedIn = user;
      final service = await AuthService(repo, ProfileService(profiles)).init();
      user.emailVerified = true;
      expect(await repo.reloadEmailVerified(), isTrue);
      service.refreshUser();
      expect(service.routeForUser, AppRoutes.home);
    });
  });

  group('Routing after sign in', () {
    Future<AuthService> signedIn({
      bool verified = true,
      String provider = 'password',
    }) {
      auth.signedIn = FakeUser(emailVerified: verified, provider: provider);
      return AuthService(repo, ProfileService(profiles)).init();
    }

    test(
      'email login with an incomplete profile shows Profile Setup',
      () async {
        final service = await signedIn();
        expect(await service.routeAfterSignIn(), AppRoutes.profileSetup);
      },
    );

    test(
      'Google login with an incomplete profile shows Profile Setup',
      () async {
        final service = await signedIn(provider: 'google.com');
        expect(await service.routeAfterSignIn(), AppRoutes.profileSetup);
      },
    );

    test('a completed profile goes straight to Home', () async {
      profiles.completeSetup('uid-1');
      for (final provider in ['password', 'google.com']) {
        final service = await signedIn(provider: provider);
        expect(await service.routeAfterSignIn(), AppRoutes.home);
      }
    });

    test('a new email account verifies before Profile Setup', () async {
      final service = await signedIn(verified: false);
      expect(
        await service.routeAfterSignIn(isNewAccount: true),
        AppRoutes.verifyEmail,
      );
      expect(profiles.migrations, isEmpty);
    });

    test('a new verified (Google) account goes to Profile Setup', () async {
      final service = await signedIn(provider: 'google.com');
      expect(
        await service.routeAfterSignIn(isNewAccount: true),
        AppRoutes.profileSetup,
      );
    });

    test('once verified, a completed profile goes to Home', () async {
      profiles.completeSetup('uid-1');
      final user = FakeUser(emailVerified: false, provider: 'password');
      auth.signedIn = user;
      final service = await AuthService(repo, ProfileService(profiles)).init();
      expect(await service.routeAfterSignIn(), AppRoutes.verifyEmail);
      user.emailVerified = true;
      await repo.reloadEmailVerified();
      service.refreshUser();
      expect(await service.routeAfterSignIn(), AppRoutes.home);
    });

    test('unverified email login verifies before the profile', () async {
      final service = await signedIn(verified: false);
      expect(await service.routeAfterSignIn(), AppRoutes.verifyEmail);
    });

    test('a profile read failure falls back to Home', () async {
      profiles.readFailure = const ProfileFailure('offline');
      final service = await signedIn();
      expect(await service.routeAfterSignIn(), AppRoutes.home);
    });

    test('restarting with a saved session skips the profile check', () async {
      final service = await signedIn();
      expect(service.initialRoute, AppRoutes.home);
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('sarah@familycare'), isNotNull);
      expect(Validators.email(' sarah@familycare.org '), isNull);
    });

    test('optional phone', () {
      expect(Validators.optionalPhone(''), isNull);
      expect(Validators.optionalPhone('(555) 432-8921'), isNull);
      expect(Validators.optionalPhone('+92 300 1234567'), isNull);
      expect(Validators.optionalPhone('12ab'), isNotNull);
      expect(Validators.optionalPhone('123'), isNotNull);
    });

    test('new password and confirmation', () {
      expect(Validators.newPassword('short1'), isNotNull);
      expect(Validators.newPassword('allletters'), isNotNull);
      expect(Validators.newPassword('letters123'), isNull);
      expect(Validators.confirmPassword('letters123', 'letters124'), isNotNull);
      expect(Validators.confirmPassword('letters123', ''), isNotNull);
      expect(Validators.confirmPassword('letters123', 'letters123'), isNull);
    });
  });
}
