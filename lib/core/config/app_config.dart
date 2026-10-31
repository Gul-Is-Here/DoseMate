import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-time configuration, passed with
/// `flutter run --dart-define-from-file=config/keys.json` (see
/// config/keys.example.json). Nothing secret is committed to source.
abstract class AppConfig {
  /// Client keys for Places API (New), in the Firebase project. A key takes
  /// one kind of app restriction, so each platform has its own: Android's
  /// is limited to this package and its signing certificates, iOS's to this
  /// bundle id, and both to Places API (New) only.
  static const placesApiKeyAndroid = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY_ANDROID',
  );
  static const placesApiKeyIos = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY_IOS',
  );

  /// This platform's Places key; empty where address search isn't set up.
  static String get placesApiKey {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return placesApiKeyAndroid;
    if (Platform.isIOS) return placesApiKeyIos;
    return '';
  }

  /// SHA-1 of the certificate this build is signed with (hex, no colons):
  /// the debug keystore's for debug builds, Play's app signing key's for
  /// Play releases. Sent with requests so the Android-restricted key
  /// accepts them; that certificate must be on the key's allowed list.
  static const androidCertSha1 = String.fromEnvironment(
    'GOOGLE_ANDROID_CERT_SHA1',
  );

  static const appId = 'com.dosemate.mobile';

  /// AdMob banner units (Android). Debug and profile builds use Google's
  /// test unit: live ads must not be shown or tapped while developing.
  static String get adBannerShell =>
      kReleaseMode ? 'ca-app-pub-2744970719381152/7980827055' : _testBanner;
  static String get adBannerDetails =>
      kReleaseMode ? 'ca-app-pub-2744970719381152/2476771821' : _testBanner;
  static const _testBanner = 'ca-app-pub-3940256099942544/9214589741';

  /// AdMob native units, shown in lists (same test rule as the banners).
  static String get adNativeMedicines =>
      kReleaseMode ? 'ca-app-pub-2744970719381152/2235218345' : _testNative;
  static String get adNativeHistory =>
      kReleaseMode ? 'ca-app-pub-2744970719381152/8687404065' : _testNative;
  static const _testNative = 'ca-app-pub-3940256099942544/2247696110';

  /// The public privacy policy (Firebase Hosting, hosting/privacy/).
  static final privacyPolicyUrl = Uri.https(
    'dosemate-70150.web.app',
    '/privacy/',
  );

  /// OAuth client ids from google-services.json / GoogleService-Info.plist.
  /// Public identifiers, not secrets.
  static const googleWebClientId =
      '1074770041543-f3n59896h0td00eacuiheme27i56agrg.apps.googleusercontent.com';
  static const googleIosClientId =
      '1074770041543-gdc1i8ubmhcom1881qgm0dvip4nr78ef.apps.googleusercontent.com';
}
