import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/theme/app_colors.dart';
import '../data/services/ads_service.dart';
import 'app_shell.dart';

/// A native ad in a list, drawn by Google's small template in the app's
/// colours (the template carries the "Ad" badge). Takes no room until an
/// ad has loaded, and none where ads are off (iOS, tests, no consent).
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({
    super.key,
    required this.unitId,
    this.padding = EdgeInsets.zero,
  });

  final String unitId;

  /// Around the ad once loaded (no gap is left while there's none).
  final EdgeInsets padding;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  Worker? _ready;

  AdsService? get _ads =>
      Get.isRegistered<AdsService>() ? Get.find<AdsService>() : null;

  @override
  void initState() {
    super.initState();
    final ads = _ads;
    if (ads == null) return;
    // Consent may finish after this screen opened.
    _ready = ever(ads.ready, (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted || _ad != null || !(_ads?.ready.value ?? false)) return;
    _ad = NativeAd(
      adUnitId: widget.unitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: AppColors.surfaceContainerLowest,
        cornerRadius: kRadiusLg,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.onPrimary,
          backgroundColor: AppColors.primary,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.onSurface,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.onSurfaceVariant,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.onSurfaceVariant,
          size: 13,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ready?.dispose();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    // Google's small template is laid out for 90 to 200 tall.
    return Padding(
      padding: widget.padding,
      child: SizedBox(height: 112, child: AdWidget(ad: ad)),
    );
  }
}
