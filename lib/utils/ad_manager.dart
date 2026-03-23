import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'const.dart';

class AdManager {
  static final AdManager instance = AdManager._internal();
  static const bool _forceTestAds = bool.fromEnvironment(
    'MUSCLECARE_FORCE_TEST_ADS',
    defaultValue: false,
  );

  factory AdManager() => instance;
  AdManager._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  bool _isInitializing = false;
  bool _initialized = false;
  bool _isLoadingInterstitial = false;

  VoidCallback? _onInterstitialAdClosed;
  Timer? _interstitialRetryTimer;
  Duration _interstitialRetryDelay = const Duration(seconds: 20);
  DateTime? _lastNetworkInterstitialErrorAt;

  Future<void> initialize() async {
    if (_initialized || _isInitializing) {
      return;
    }

    _isInitializing = true;
    try {
      if (kDebugMode) {
        final platform = Platform.isAndroid
            ? 'Android'
            : (Platform.isIOS ? 'iOS' : 'Unknown');
        const mode = kReleaseMode ? 'Release' : 'Debug';
        debugPrint('MobileAds init start ($platform / $mode)');
      }

      await MobileAds.instance.initialize();
      if (kDebugMode) {
        debugPrint('MobileAds init done');
      }

      _initialized = true;
      loadInterstitialAd();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('MobileAds init failed: $e');
        debugPrint('$stackTrace');
      }
      _initialized = false;
    } finally {
      _isInitializing = false;
    }
  }

  bool get isInterstitialAdReady => _isInterstitialAdReady;
  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  String get interstitialAdUnitId {
    if (!isSupportedPlatform) {
      throw UnsupportedError('Unsupported platform');
    }
    if (_forceTestAds) {
      return AdConstants.testInterstitial;
    }

    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return AdConstants.releaseAndroidInterstitial;
      }
      if (Platform.isIOS) {
        return AdConstants.releaseIosInterstitial;
      }
    } else {
      return AdConstants.testInterstitial;
    }
    throw UnsupportedError('Unsupported platform');
  }

  String get bannerAdUnitId {
    if (!isSupportedPlatform) {
      throw UnsupportedError('Unsupported platform');
    }
    if (_forceTestAds) {
      if (Platform.isAndroid) {
        return AdConstants.testAndroidBanner;
      }
      if (Platform.isIOS) {
        return AdConstants.testIoSBanner;
      }
      throw UnsupportedError('Unsupported platform');
    }

    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return AdConstants.releaseAndroidBanner;
      }
      if (Platform.isIOS) {
        return AdConstants.releaseIosBanner;
      }
    } else {
      if (Platform.isAndroid) {
        return AdConstants.testAndroidBanner;
      }
      if (Platform.isIOS) {
        return AdConstants.testIoSBanner;
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  BannerAd createBannerAd({
    required BannerAdListener listener,
    AdSize size = AdSize.banner,
  }) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: listener,
    );
  }

  void showInterstitialAd({required VoidCallback onClosed}) {
    if (_isInterstitialAdReady && _interstitialAd != null) {
      _onInterstitialAdClosed = onClosed;
      try {
        _interstitialAd!.show();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Interstitial show failed: $e');
        }
        _isInterstitialAdReady = false;
        _interstitialAd?.dispose();
        _interstitialAd = null;
        _onInterstitialAdClosed?.call();
        _onInterstitialAdClosed = null;
        loadInterstitialAd(force: true);
      }
    } else {
      loadInterstitialAd(force: true);
      onClosed();
    }
  }

  void loadInterstitialAd({bool force = false}) {
    if (!_initialized) {
      unawaited(initialize());
      return;
    }

    if (_isLoadingInterstitial) {
      return;
    }
    if (!force && _isInterstitialAdReady) {
      return;
    }

    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = null;
    _isLoadingInterstitial = true;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialAdReady = false;

    final adUnitId = interstitialAdUnitId;
    try {
      InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoadingInterstitial = false;
            _interstitialAd = ad;
            _isInterstitialAdReady = true;
            _interstitialRetryDelay = const Duration(seconds: 20);
            _interstitialAd?.fullScreenContentCallback =
                FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                _isInterstitialAdReady = false;
                ad.dispose();
                _interstitialAd = null;
                _onInterstitialAdClosed?.call();
                _onInterstitialAdClosed = null;
                loadInterstitialAd();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                if (kDebugMode) {
                  debugPrint(
                    'Interstitial show callback failed: ${error.message} (${error.code})',
                  );
                }
                _isInterstitialAdReady = false;
                ad.dispose();
                _interstitialAd = null;
                _onInterstitialAdClosed?.call();
                _onInterstitialAdClosed = null;
                loadInterstitialAd();
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isLoadingInterstitial = false;
            if (kDebugMode && _shouldLogInterstitialLoadFailure(error)) {
              debugPrint(
                'Interstitial load failed: ${error.message} (${error.code}) / $adUnitId',
              );
            }
            _isInterstitialAdReady = false;
            _interstitialAd = null;
            _scheduleInterstitialRetry();
          },
        ),
      );
    } catch (e, stackTrace) {
      _isLoadingInterstitial = false;
      if (kDebugMode) {
        debugPrint('Interstitial load exception: $e');
        debugPrint('$stackTrace');
      }
      _isInterstitialAdReady = false;
      _interstitialAd = null;
    }
  }

  void dispose() {
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialAdReady = false;
    _isLoadingInterstitial = false;
    _onInterstitialAdClosed = null;
  }

  bool _shouldLogInterstitialLoadFailure(LoadAdError error) {
    if (error.code != 2) {
      return true;
    }
    final now = DateTime.now();
    final last = _lastNetworkInterstitialErrorAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return false;
    }
    _lastNetworkInterstitialErrorAt = now;
    return true;
  }

  void _scheduleInterstitialRetry() {
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = Timer(_interstitialRetryDelay, () {
      loadInterstitialAd(force: true);
    });
    final nextSeconds = (_interstitialRetryDelay.inSeconds * 2).clamp(20, 300);
    _interstitialRetryDelay = Duration(seconds: nextSeconds.toInt());
  }
}
