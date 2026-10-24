import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';

/// Thrown when the user closes the Google account picker.
class GooglePickerCancelled implements Exception {
  const GooglePickerCancelled();
}

/// Thrown when the picker fails for another reason.
class GooglePickerFailure implements Exception {
  const GooglePickerFailure(this.code);

  /// [GoogleSignInExceptionCode] name, for diagnostics only.
  final String code;
}

/// The device's native Google account chooser (Credential Manager on
/// Android, Google Sign-In on iOS), so sign in never leaves the app for a
/// browser. Returns an ID token for Firebase; nothing is stored here.
class GoogleAccountPicker {
  bool? _ready;

  bool get isSupported => GoogleSignIn.instance.supportsAuthenticate();

  Future<void> _init() async {
    if (_ready == true) return;
    await GoogleSignIn.instance.initialize(
      clientId: AppConfig.googleIosClientId,
      // Firebase verifies the ID token against the web client.
      serverClientId: AppConfig.googleWebClientId,
    );
    _ready = true;
  }

  Future<String> idToken() async {
    await _init();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const GooglePickerFailure('no-id-token');
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const GooglePickerCancelled();
      }
      throw GooglePickerFailure(e.code.name);
    }
  }

  /// Forgets the chosen account so the chooser appears next time.
  Future<void> signOut() async {
    if (_ready != true) return;
    try {
      await GoogleSignIn.instance.signOut();
    } on Exception {
      // Firebase sign out already happened; nothing else to clean up.
    }
  }
}
