import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/supabase_runtime_state.dart';
import '../theme/app_theme.dart';
import '../utils/ad_manager.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.showPlaceholder = true,
    this.placeholderText = 'ads.loading',
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.backgroundColor = const Color(0x141C212D),
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
  Duration _retryDelay = const Duration(seconds: 8);
  static DateTime? _lastNetworkBannerErrorAt;
  static DateTime? _bannerRetryCooldownUntil;
  int _retryCount = 0;
  static const int _maxRetryCount = 1;

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

  Future<void> _loadBannerAd() async {
    final cooldownUntil = _bannerRetryCooldownUntil;
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return;
    }
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    if (mounted) {
      setState(() {
        _isLoaded = false;
      });
    } else {
      _isLoaded = false;
    }

    // Flutter tester/macOS/web 환경에서는 네이티브 광고 플러그인이 없으므로
    // placeholder만 표시하고 광고 로딩을 생략한다.
    if (!AdManager.instance.isSupportedPlatform) {
      return;
    }
    if (SupabaseRuntimeState.isTemporarilySuspended) {
      return;
    }

    final loadToken = ++_loadToken;
    await AdManager.instance.initialize();
    if (!mounted || loadToken != _loadToken) {
      return;
    }

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
          _retryDelay = const Duration(seconds: 8);
          _retryCount = 0;
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (!mounted || loadToken != _loadToken) {
            return;
          }
          if (kDebugMode && _shouldLogBannerLoadFailure(error)) {
            debugPrint('Banner load failed: ${error.message} (${error.code})');
          }
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
          _retryCount += 1;
          final shouldRetry = _retryCount <= _maxRetryCount;
          if (shouldRetry) {
            _retryTimer = Timer(_retryDelay, () {
              unawaited(_loadBannerAd());
            });
            final nextSeconds = (_retryDelay.inSeconds * 2).clamp(8, 120);
            _retryDelay = Duration(seconds: nextSeconds.toInt());
          } else {
            _bannerRetryCooldownUntil = DateTime.now().add(
              const Duration(minutes: 10),
            );
          }
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
        widget.placeholderText.tr(),
        style: TextStyle(
          color: AppTheme.textLow,
          fontSize: 12,
        ),
      ),
    );
  }

  bool _shouldLogBannerLoadFailure(LoadAdError error) {
    if (error.code != 2) {
      return true;
    }
    final now = DateTime.now();
    final last = _lastNetworkBannerErrorAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return false;
    }
    _lastNetworkBannerErrorAt = now;
    return true;
  }
}
