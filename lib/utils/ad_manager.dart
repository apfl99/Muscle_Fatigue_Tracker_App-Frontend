import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';
import 'const.dart';

class AdManager {
  static final AdManager instance = AdManager._internal();
  factory AdManager() => instance;
  AdManager._internal();

  AppOpenAd? _splashAd;
  InterstitialAd? _interstitialAd;
  bool _isSplashAdReady = false;
  bool _isInterstitialAdReady = false;

  // Ad callbacks
  Function? onSplashAdClosed;
  Function? onInterstitialAdClosed;

  // Ad initialization
  Future<void> initialize() async {
    try {
      debugPrint('📱 MobileAds 초기화 시작...');
      await MobileAds.instance.initialize();
      debugPrint('✅ MobileAds 초기화 완료');

      debugPrint('📥 전면 광고 로드 시작...');
      // 스플래시 화면에서 InterstitialAd만 사용하므로 InterstitialAd만 로드
      await loadInterstitialAd();
      debugPrint('✅ 광고 로드 완료');
    } catch (e) {
      debugPrint('❌ AdMob 초기화 실패: $e');
    }
  }

  // Show splash ad (AppOpenAd)
  Future<void> showSplashAd({required Function onClosed}) async {
    onSplashAdClosed = onClosed;
    if (_isSplashAdReady && _splashAd != null) {
      try {
        debugPrint('Attempting to show Splash Ad');
        await _splashAd!.show();
      } catch (e) {
        debugPrint('Error showing Splash Ad: $e');
        _isSplashAdReady = false;
        _splashAd?.dispose();
        onSplashAdClosed?.call();
        onSplashAdClosed = null;
      }
    } else {
      debugPrint('Splash Ad not ready, skipping');
      onClosed();
    }
  }

  // Show Interstitial ad
  void showInterstitialAd({required Function onClosed}) {
    if (_isInterstitialAdReady && _interstitialAd != null) {
      onInterstitialAdClosed = onClosed;
      try {
        debugPrint('📺 전면 광고 표시 시도');
        _interstitialAd!.show();
      } catch (e) {
        debugPrint('❌ 전면 광고 표시 오류: $e');
        _isInterstitialAdReady = false;
        _interstitialAd?.dispose();
        onInterstitialAdClosed?.call();
        onInterstitialAdClosed = null;
      }
    } else {
      debugPrint('⚠️ 전면 광고가 준비되지 않음');
      onClosed();
    }
  }

  void dispose() {
    _splashAd?.dispose();
    _interstitialAd?.dispose();
    onSplashAdClosed = null;
    onInterstitialAdClosed = null;
  }

  bool get isInterstitialAdReady => _isInterstitialAdReady;
  bool get isSplashAdReady => _isSplashAdReady;

  String get splashAdUnitId {
    // 스플래시 화면에서 InterstitialAd를 사용하므로 InterstitialAd ID 반환
    return interstitialAdUnitId;
  }

  String get interstitialAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return AdConstants.releaseAndroidAdMob;
      } else if (Platform.isIOS) {
        return AdConstants.releaseIosAdMob;
      }
    } else {
      return AdConstants.testInterstitial;
    }
    throw UnsupportedError('Unsupported platform');
  }

  Future<void> loadSplashAd() async {
    if (_isSplashAdReady) {
      debugPrint('✅ 스플래시 광고 이미 준비됨');
      return;
    }

    final adUnitId = splashAdUnitId;
    debugPrint('📥 스플래시 광고 로드 시작: $adUnitId');

    try {
      await AppOpenAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('✅ 스플래시 광고 로드 성공');
            _splashAd = ad;
            _isSplashAdReady = true;
            _splashAd?.fullScreenContentCallback = FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {
                debugPrint('📺 스플래시 광고 표시됨');
              },
              onAdDismissedFullScreenContent: (ad) {
                debugPrint('✅ 스플래시 광고 닫힘');
                _isSplashAdReady = false;
                ad.dispose();
                onSplashAdClosed?.call();
                onSplashAdClosed = null;
                // Preload next ad
                loadSplashAd();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                debugPrint(
                  '❌ 스플래시 광고 표시 실패: ${error.message} (code: ${error.code})',
                );
                _isSplashAdReady = false;
                ad.dispose();
                onSplashAdClosed?.call();
                onSplashAdClosed = null;
                // Preload next ad
                loadSplashAd();
              },
            );
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              '❌ 스플래시 광고 로드 실패: ${error.message} (code: ${error.code})',
            );
            debugPrint('   광고 Unit ID: $adUnitId');
            _isSplashAdReady = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ 스플래시 광고 로드 예외: $e');
      _isSplashAdReady = false;
    }
  }

  Future<void> loadInterstitialAd() async {
    if (_isInterstitialAdReady) {
      debugPrint('✅ 전면 광고 이미 준비됨');
      return;
    }

    final adUnitId = interstitialAdUnitId;
    debugPrint('📥 전면 광고 로드 시작: $adUnitId');

    try {
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('✅ 전면 광고 로드 성공');
            _interstitialAd = ad;
            _isInterstitialAdReady = true;
            _interstitialAd?.fullScreenContentCallback =
                FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {
                debugPrint('📺 전면 광고 표시됨');
              },
              onAdDismissedFullScreenContent: (ad) {
                debugPrint('✅ 전면 광고 닫힘');
                _isInterstitialAdReady = false;
                ad.dispose();
                onInterstitialAdClosed?.call();
                onInterstitialAdClosed = null;
                // Preload next ad
                loadInterstitialAd();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                debugPrint(
                  '❌ 전면 광고 표시 실패: ${error.message} (code: ${error.code})',
                );
                _isInterstitialAdReady = false;
                ad.dispose();
                onInterstitialAdClosed?.call();
                onInterstitialAdClosed = null;
                // Preload next ad
                loadInterstitialAd();
              },
            );
          },
          onAdFailedToLoad: (error) {
            debugPrint('❌ 전면 광고 로드 실패: ${error.message} (code: ${error.code})');
            debugPrint('   광고 Unit ID: $adUnitId');
            debugPrint('   에러 도메인: ${error.domain}');
            debugPrint('   에러 원인: ${error.responseInfo}');
            _isInterstitialAdReady = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ 전면 광고 로드 예외: $e');
      _isInterstitialAdReady = false;
    }
  }
}
