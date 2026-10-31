import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner ads (AdMob, Android only). Ads are requested only after Google's
/// consent message has run where the law requires one (EEA, UK,
/// Switzerland); a failure anywhere just means no ads.
// shortcut: no ads on iOS; ios/Runner/Info.plist holds Google's sample
// GADApplicationIdentifier only because the SDK won't start without one.
// Replace it with an iOS AdMob app id (and iOS units) to show ads there.
class AdsService extends GetxService {
  /// True once banners may load.
  final ready = false.obs;

  /// The user must be able to change their ad consent (Settings shows a row).
  final privacyOptionsRequired = false.obs;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// After the first frame: the consent form needs a visible screen.
  Future<void> start() async {
    if (!supported || ready.value) return;
    try {
      final consent = ConsentInformation.instance;
      final done = Completer<void>();
      consent.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired(
          (_) => done.complete(),
        ),
        // Offline: consent from an earlier session still counts below.
        (_) => done.complete(),
      );
      await done.future;
      privacyOptionsRequired.value =
          await consent.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!await consent.canRequestAds()) return;
      await MobileAds.instance.initialize();
      ready.value = true;
    } catch (e) {
      _log('start', e);
    }
  }

  /// Settings › Ad privacy choices: change consent given earlier.
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
      // Consent may now be withdrawn: banners already shown stay until
      // their screen closes; new ones follow the new choice.
      ready.value = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      _log('privacy', e);
    }
  }

  // Error types only.
  static void _log(String step, Object e) {
    if (kDebugMode) debugPrint('Ads $step error: ${e.runtimeType}');
  }
}
