import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/google_account_picker.dart';

/// A user-facing auth error. [message] is safe to show in the UI.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;

  /// Firebase error code, for handling (e.g. rate limits); never shown.
  final String? code;
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

  /// Creates the account and sends the verification email. Returns
  /// whether the email was sent: the account exists either way, so a failed
  /// send is not a failed sign up (the Verify Email screen offers Resend).
  Future<bool> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final user = await _guard(() async {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user!;
      await user.updateDisplayName(name);
      return user;
    });
    try {
      await user.sendEmailVerification();
      return true;
    } on FirebaseAuthException catch (e) {
      // Code only; never the address.
      if (kDebugMode) debugPrint('Verification email not sent: ${e.code}');
      return false;
    }
  }

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

  /// Fetches the latest verification state from Firebase. Once verified,
  /// refreshes the ID token so Firestore and Storage rules see the new
  /// `email_verified` claim straight away.
  Future<bool> reloadEmailVerified() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final current = _auth.currentUser;
    if (current == null || !current.emailVerified) return false;
    await current.getIdToken(true);
    return true;
  });

  /// How the signed-in account can confirm it's them: a password when it
  /// has one, otherwise Google.
  bool get hasPassword =>
      _auth.currentUser?.providerData.any(
        (p) => p.providerId == EmailAuthProvider.PROVIDER_ID,
      ) ??
      false;

  bool get hasGoogle =>
      _auth.currentUser?.providerData.any(
        (p) => p.providerId == GoogleAuthProvider.PROVIDER_ID,
      ) ??
      false;

  /// Confirms the signed-in user with their password, for actions that need
  /// a recent sign in. The password goes to Firebase only.
  Future<void> reauthenticateWithPassword(String password) => _guard(() async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    // A fresh ID token carries the new sign-in time to the server.
    await user.getIdToken(true);
  }, reauth: true);

  /// Confirms the signed-in user with Google. Choosing a different Google
  /// account fails with `user-mismatch` and changes nothing.
  Future<void> reauthenticateWithGoogle() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'user-not-found');
    if (kIsWeb) {
      await user.reauthenticateWithPopup(
        GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
      );
    } else if (_google.isSupported) {
      final String idToken;
      try {
        idToken = await _google.idToken();
      } on GooglePickerCancelled {
        throw const AuthCancelled();
      } on GooglePickerFailure catch (e) {
        if (kDebugMode) debugPrint('Google picker error: ${e.code}');
        throw const AuthFailure(
          "Couldn't open Google. Check your connection and try again.",
        );
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } else {
      await user.reauthenticateWithProvider(GoogleAuthProvider());
    }
    await user.getIdToken(true);
  }, reauth: true);

  /// Signs out. [revokeGoogle] also withdraws the app's access to the
  /// Google account (after account deletion), not just this session.
  Future<void> signOut({bool revokeGoogle = false}) async {
    await _auth.signOut();
    await (revokeGoogle ? _google.disconnect() : _google.signOut());
  }

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool reauth = false,
  }) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      if (_cancelCodes.contains(e.code)) throw const AuthCancelled();
      final message = reauth ? _reauthMessages[e.code] : null;
      throw AuthFailure(message ?? _messageFor(e.code), code: e.code);
    }
  }

  static const _reauthMessages = {
    'wrong-password': 'That password isn’t right. Try again.',
    'invalid-credential': 'That password isn’t right. Try again.',
    'INVALID_LOGIN_CREDENTIALS': 'That password isn’t right. Try again.',
    'user-mismatch':
        'That’s a different account. Choose the one you signed in with.',
    'user-not-found': 'This account no longer exists.',
    'user-token-expired': 'You were signed out. Sign in again to continue.',
  };

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
