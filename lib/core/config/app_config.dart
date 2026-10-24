/// Build-time configuration, passed with
/// `flutter run --dart-define-from-file=config/keys.json` (see
/// config/keys.example.json). Nothing secret is committed to source.
abstract class AppConfig {
  /// Client key for Places API (New), restricted to this app's Android
  /// package/certificate and iOS bundle id, and to Places API (New) only.
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// SHA-1 of the Android signing certificate (hex, no colons). Sent with
  /// requests so an Android-restricted key accepts them.
  static const androidCertSha1 = String.fromEnvironment(
    'GOOGLE_ANDROID_CERT_SHA1',
  );

  static const appId = 'com.dosemate.app';

  /// OAuth client ids from google-services.json / GoogleService-Info.plist.
  /// Public identifiers, not secrets.
  static const googleWebClientId =
      '1074770041543-f3n59896h0td00eacuiheme27i56agrg.apps.googleusercontent.com';
  static const googleIosClientId =
      '1074770041543-tkgn7pka7q1j80ja72evbgobbg40lnmk.apps.googleusercontent.com';
}
