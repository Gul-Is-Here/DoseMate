import 'dart:async';

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/core/utils/validators.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

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
  bool emailVerified;

  @override
  final List<UserInfo> providerData;

  String? name;
  int verificationEmails = 0;

  @override
  String? get email => 'a@b.co';

  @override
  Future<void> updateDisplayName(String? displayName) async =>
      name = displayName;

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async =>
      verificationEmails++;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    return FakeCredential(user);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => _complete(FakeUser(emailVerified: false, provider: 'password'));

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _complete(FakeUser(emailVerified: true, provider: 'password'));

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) =>
      _complete(FakeUser(emailVerified: true, provider: 'google.com'));

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

  setUp(() {
    auth = FakeAuth();
    repo = AuthRepository(auth);
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

    test('Google sign in succeeds and needs no email verification', () async {
      await repo.signInWithGoogle();
      expect(AuthRepository.needsEmailVerification(auth.signedIn!), isFalse);
    });

    test('closing the Google sheet is a cancellation, not an error', () async {
      auth.nextError = FirebaseAuthException(code: 'web-context-canceled');
      await expectLater(repo.signInWithGoogle(), throwsA(isA<AuthCancelled>()));
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
      final service = await AuthService(repo).init();
      expect(service.initialRoute, AppRoutes.onboarding);
    });

    test('restored verified session routes to home', () async {
      auth.signedIn = FakeUser(emailVerified: true, provider: 'password');
      final service = await AuthService(repo).init();
      expect(service.initialRoute, AppRoutes.home);
    });

    test('restored unverified email session routes to verification', () async {
      auth.signedIn = FakeUser(emailVerified: false, provider: 'password');
      final service = await AuthService(repo).init();
      expect(service.initialRoute, AppRoutes.verifyEmail);
    });

    test('verification picks up after reload', () async {
      final user = FakeUser(emailVerified: false, provider: 'password');
      auth.signedIn = user;
      final service = await AuthService(repo).init();
      user.emailVerified = true;
      expect(await repo.reloadEmailVerified(), isTrue);
      service.refreshUser();
      expect(service.routeForUser, AppRoutes.home);
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('sarah@familycare'), isNotNull);
      expect(Validators.email(' sarah@familycare.org '), isNull);
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
