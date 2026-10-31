import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/services/ads_service.dart';

/// An AdMob banner as wide as its space. Takes no room until an ad has
/// loaded, and none at all where ads are off (iOS, tests, no consent).
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, required this.unitId, this.inline = false});

  final String unitId;

  /// In scrolling content (up to 250 tall) rather than anchored to the
  /// screen edge (Google's large anchored size).
  final bool inline;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  Size? _size;
  int? _width;
  Worker? _ready;

  AdsService? get _ads =>
      Get.isRegistered<AdsService>() ? Get.find<AdsService>() : null;

  @override
  void initState() {
    super.initState();
    // Consent may finish after this screen opened.
    final ads = _ads;
    if (ads != null) _ready = ever(ads.ready, (_) => _load());
  }

  Future<void> _load() async {
    final width = _width;
    if (!mounted || width == null || _ad != null) return;
    if (!(_ads?.ready.value ?? false)) return;
    final size = widget.inline
        ? AdSize.getInlineAdaptiveBannerAdSize(width, 250)
        : await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null || _ad != null) return;
    final ad = BannerAd(
      adUnitId: widget.unitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          // Inline banners choose their height when they load.
          final real = await (ad as BannerAd).getPlatformAdSize();
          if (!mounted) return;
          setState(() {
            _size = Size(
              (real ?? size).width.toDouble(),
              (real ?? size).height.toDouble(),
            );
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ready?.dispose();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ads == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.truncate();
        if (_width != width && _ad == null) {
          _width = width;
          WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        }
        final ad = _ad;
        final size = _size;
        if (ad == null || size == null) return const SizedBox.shrink();
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: AdWidget(ad: ad),
          ),
        );
      },
    );
  }
}
