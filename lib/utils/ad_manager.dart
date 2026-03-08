import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'const.dart';

class AdManager {
  static final AdManager instance = AdManager._internal();
  factory AdManager() => instance;
  AdManager._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  bool _isInitializing = false;
  bool _initialized = false;
  bool _isLoadingInterstitial = false;

  VoidCallback? _onInterstitialAdClosed;

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

      loadInterstitialAd();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('MobileAds init failed: $e');
        debugPrint('$stackTrace');
      }
    } finally {
      _initialized = true;
      _isInitializing = false;
    }
  }

  bool get isInterstitialAdReady => _isInterstitialAdReady;

  String get interstitialAdUnitId {
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
      onClosed();
    }
  }

  void loadInterstitialAd({bool force = false}) {
    if (_isLoadingInterstitial) {
      return;
    }
    if (!force && _isInterstitialAdReady) {
      return;
    }

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
            if (kDebugMode) {
              debugPrint(
                'Interstitial load failed: ${error.message} (${error.code}) / $adUnitId',
              );
            }
            _isInterstitialAdReady = false;
            _interstitialAd = null;
            Timer(const Duration(seconds: 20), () {
              loadInterstitialAd(force: true);
            });
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
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialAdReady = false;
    _isLoadingInterstitial = false;
    _onInterstitialAdClosed = null;
  }
}
