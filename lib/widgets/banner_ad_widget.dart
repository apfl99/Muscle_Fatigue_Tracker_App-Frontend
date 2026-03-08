import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../utils/ad_manager.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.showPlaceholder = true,
    this.placeholderText = '광고 로딩 중',
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.backgroundColor = const Color(0x08FFFFFF),
  });

  final AdSize adSize;
  final bool showPlaceholder;
  final String placeholderText;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBannerAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _bannerAd == null) {
      _loadBannerAd();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  void _loadBannerAd() {
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;

    final loadToken = ++_loadToken;
    final ad = AdManager.instance.createBannerAd(
      size: widget.adSize,
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted || loadToken != _loadToken) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _bannerAd = loadedAd as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (!mounted || loadToken != _loadToken) {
            return;
          }
          if (kDebugMode) {
            debugPrint('Banner load failed: ${error.message} (${error.code})');
          }
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
          _retryTimer = Timer(const Duration(seconds: 20), _loadBannerAd);
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _bannerAd != null) {
      final ad = _bannerAd!;
      return Container(
        alignment: Alignment.center,
        padding: widget.padding,
        color: widget.backgroundColor,
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      );
    }

    if (!widget.showPlaceholder) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      padding: widget.padding,
      color: widget.backgroundColor,
      child: Text(
        widget.placeholderText,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
        ),
      ),
    );
  }
}
