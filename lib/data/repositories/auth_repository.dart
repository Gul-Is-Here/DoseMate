import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/google_account_picker.dart';

/// A user-facing auth error. [message] is safe to show in the UI.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;
}

/// The user dismissed the Google sign-in flow.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Thin wrapper over [FirebaseAuth]. Firebase holds the session; nothing
/// sensitive (passwords, tokens) is stored or logged here.
class AuthRepository {
  AuthRepository(this._auth, {GoogleAccountPicker? googlePicker})
    : _google = googlePicker ?? GoogleAccountPicker();

  final FirebaseAuth _auth;
  final GoogleAccountPicker _google;

  static const _cancelCodes = {
    'canceled',
    'cancelled',
    'web-context-canceled',
    'web-context-cancelled',
    'popup-closed-by-user',
    'cancelled-popup-request',
    'user-cancelled',
  };

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Email/password accounts must verify their email before using the app.
  static bool needsEmailVerification(User user) =>
      !user.emailVerified &&
      user.providerData.any(
        (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
      );

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(name);
    await user.sendEmailVerification();
  });

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  /// Signs in or creates an account with Google. On Android and iOS the
  /// native account chooser supplies an ID token, so the app never hands
  /// off to a browser; elsewhere Firebase's own provider flow is used. Firebase rejects (rather than merges) an email that already
  /// belongs to a different account with `account-exists-with-different-credential`.
  /// Returns whether this sign in created the account.
  Future<bool> signInWithGoogle() => _guard(() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    final UserCredential credential;
    if (kIsWeb) {
      credential = await _auth.signInWithPopup(provider);
    } else if (_google.isSupported) {
      final String idToken;
      try {
        idToken = await _google.idToken();
      } on GooglePickerCancelled {
        throw const AuthCancelled();
      } on GooglePickerFailure catch (e) {
        if (kDebugMode) debugPrint('Google picker error: ${e.code}');
        throw const AuthFailure(
          "Couldn't open Google sign in. Check your connection and try again.",
        );
      }
      credential = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } else {
      credential = await _auth.signInWithProvider(provider);
    }
    return credential.additionalUserInfo?.isNewUser ?? false;
  });

  /// Completes silently when no account exists, so the response never reveals
  /// whether an email is registered.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      throw AuthFailure(_messageFor(e.code));
    }
  }

  Future<void> sendEmailVerification() =>
      _guard(() => _auth.currentUser!.sendEmailVerification());

  /// Fetches the latest verification state from Firebase.
  Future<bool> reloadEmailVerified() => _guard(() async {
    await _auth.currentUser!.reload();
    return _auth.currentUser?.emailVerified ?? false;
  });

  Future<void> signOut() async {
    await _auth.signOut();
    await _google.signOut();
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      if (_cancelCodes.contains(e.code)) throw const AuthCancelled();
      throw AuthFailure(_messageFor(e.code));
    }
  }

  static String _messageFor(String code) => switch (code) {
    'invalid-email' => 'Enter a valid email address.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' ||
    'INVALID_LOGIN_CREDENTIALS' => 'Incorrect email or password.',
    'email-already-in-use' => 'An account already exists for this email. Sign in instead, or reset your password.',
    'account-exists-with-different-credential' =>
      'This email is already registered with a different sign-in method. '
          'Sign in with that method instead.',
    'credential-already-in-use' =>
      'This Google account is already linked to another user.',
    'weak-password' => 'Choose a stronger password.',
    'too-many-requests' =>
      'Too many attempts. Please wait a moment and try again.',
    'network-request-failed' =>
      'No internet connection. Check your network and try again.',
    'operation-not-allowed' => 'This sign-in method is not enabled yet.',
    'requires-recent-login' => 'Please sign in again to continue.',
    _ => 'Something went wrong. Please try again.',
  };
}
