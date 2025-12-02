import 'dart:async';
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
  BannerAd? _bannerAd;
  bool _isSplashAdReady = false;
  bool _isInterstitialAdReady = false;
  bool _isBannerAdReady = false;
  bool _isLoadingBanner = false;
  Timer? _bannerRetryTimer;

  final ValueNotifier<int> bannerStateNotifier = ValueNotifier<int>(0);

  // Ad callbacks
  Function? onSplashAdClosed;
  Function? onInterstitialAdClosed;

  // Ad initialization
  Future<void> initialize() async {
    try {
      final platform =
          Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown');
      const mode = kReleaseMode ? 'Release' : 'Debug';
      debugPrint('📱 MobileAds 초기화 시작... (Platform: $platform, Mode: $mode)');

      final initStatus = await MobileAds.instance.initialize();
      debugPrint('✅ MobileAds 초기화 완료');
      debugPrint('   초기화 상태: ${initStatus.adapterStatuses}');

      debugPrint('📥 전면 광고 로드 시작...');
      // 스플래시 화면에서 InterstitialAd만 사용하므로 InterstitialAd만 로드
      // InterstitialAd.load()는 콜백 기반이므로 await 사용하지 않음
      loadInterstitialAd();
      debugPrint('✅ 광고 로드 요청 완료 (콜백으로 처리됨)');
    } catch (e, stackTrace) {
      debugPrint('❌ AdMob 초기화 실패: $e');
      debugPrint('스택 트레이스: $stackTrace');
    }
  }

  // Show splash ad (AppOpenAd)
  void showSplashAd({required Function onClosed}) {
    onSplashAdClosed = onClosed;
    if (_isSplashAdReady && _splashAd != null) {
      try {
        debugPrint('📺 스플래시 광고 표시 시도');
        _splashAd!.show();
      } catch (e) {
        debugPrint('❌ 스플래시 광고 표시 오류: $e');
        _isSplashAdReady = false;
        _splashAd?.dispose();
        onSplashAdClosed?.call();
        onSplashAdClosed = null;
      }
    } else {
      debugPrint('⚠️ 스플래시 광고가 준비되지 않음');
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
    _bannerAd?.dispose();
    onSplashAdClosed = null;
    onInterstitialAdClosed = null;
  }

  bool get isInterstitialAdReady => _isInterstitialAdReady;
  bool get isSplashAdReady => _isSplashAdReady;
  bool get isBannerAdReady => _isBannerAdReady;
  BannerAd? get bannerAd => _bannerAd;

  String get splashAdUnitId {
    // 스플래시 화면에서 InterstitialAd를 사용하므로 InterstitialAd ID 반환
    return interstitialAdUnitId;
  }

  String get interstitialAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) {
        return AdConstants.releaseAndroidInterstitial;
      } else if (Platform.isIOS) {
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
      } else if (Platform.isIOS) {
        return AdConstants.releaseIosBanner;
      }
    } else {
      if (Platform.isAndroid) {
        return AdConstants.testAndroidBanner;
      } else if (Platform.isIOS) {
        return AdConstants.testIoSBanner;
      }
    }
    throw UnsupportedError('Unsupported platform');
  }

  void loadSplashAd() {
    if (_isSplashAdReady) {
      debugPrint('✅ 스플래시 광고 이미 준비됨');
      return;
    }

    final adUnitId = splashAdUnitId;
    debugPrint('📥 스플래시 광고 로드 시작: $adUnitId');

    try {
      // AppOpenAd.load()는 콜백 기반이므로 await 사용하지 않음
      AppOpenAd.load(
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

  void loadInterstitialAd() {
    if (_isInterstitialAdReady) {
      debugPrint('✅ 전면 광고 이미 준비됨');
      return;
    }

    final adUnitId = interstitialAdUnitId;
    final platform =
        Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown');
    const mode = kReleaseMode ? 'Release' : 'Debug';
    debugPrint('📥 전면 광고 로드 시작');
    debugPrint('   플랫폼: $platform');
    debugPrint('   모드: $mode');
    debugPrint('   광고 Unit ID: $adUnitId');

    try {
      // InterstitialAd.load()는 콜백 기반이므로 await 사용하지 않음
      InterstitialAd.load(
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
                debugPrint('   에러 도메인: ${error.domain}');
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
            debugPrint('❌ 전면 광고 로드 실패');
            debugPrint('   에러 메시지: ${error.message}');
            debugPrint('   에러 코드: ${error.code}');
            debugPrint('   에러 도메인: ${error.domain}');
            debugPrint('   광고 Unit ID: $adUnitId');
            debugPrint('   플랫폼: $platform');
            debugPrint('   모드: $mode');
            if (error.responseInfo != null) {
              debugPrint('   응답 정보: ${error.responseInfo}');
            }
            _isInterstitialAdReady = false;
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 전면 광고 로드 예외: $e');
      debugPrint('스택 트레이스: $stackTrace');
      _isInterstitialAdReady = false;
    }
  }

  void loadBannerAd({bool force = false}) {
    _loadBannerAdInternal(force: force);
  }

  void _loadBannerAdInternal({bool force = false}) {
    if (!force && _isBannerAdReady) {
      debugPrint('✅ 배너 광고 이미 준비됨');
      return;
    }
    if (_isLoadingBanner) {
      debugPrint('ℹ️ 배너 광고 로딩 중...');
      return;
    }

    _isLoadingBanner = true;
    final adUnitId = bannerAdUnitId;
    final platform =
        Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown');
    const mode = kReleaseMode ? 'Release' : 'Debug';
    debugPrint('📥 배너 광고 로드 시작');
    debugPrint('   플랫폼: $platform');
    debugPrint('   모드: $mode');
    debugPrint('   광고 Unit ID: $adUnitId');

    try {
      _bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('✅ 배너 광고 로드 성공');
            _isBannerAdReady = true;
            _bannerAd = ad as BannerAd;
            _isLoadingBanner = false;
            _bannerRetryTimer?.cancel();
            _notifyBannerStateChanged();
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('❌ 배너 광고 로드 실패');
            debugPrint('   에러 메시지: ${error.message}');
            debugPrint('   에러 코드: ${error.code}');
            debugPrint('   에러 도메인: ${error.domain}');
            debugPrint('   광고 Unit ID: $adUnitId');
            debugPrint('   플랫폼: $platform');
            debugPrint('   모드: $mode');
            _isBannerAdReady = false;
            _bannerAd = null; // 실패 시 null로 설정
            ad.dispose();
            _isLoadingBanner = false;
            _scheduleBannerRetry();
            _notifyBannerStateChanged();
          },
          onAdOpened: (ad) {
            debugPrint('📺 배너 광고 클릭됨');
          },
          onAdClosed: (ad) {
            debugPrint('✅ 배너 광고 닫힘');
          },
        ),
      );
      _bannerAd?.load();
    } catch (e, stackTrace) {
      debugPrint('❌ 배너 광고 로드 예외: $e');
      debugPrint('스택 트레이스: $stackTrace');
      _isBannerAdReady = false;
      _isLoadingBanner = false;
      _scheduleBannerRetry();
      _notifyBannerStateChanged();
    }
  }

  void disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isBannerAdReady = false;
    _isLoadingBanner = false;
    _bannerRetryTimer?.cancel();
    _bannerRetryTimer = null;
    debugPrint('🗑️ 배너 광고 해제됨');
    _notifyBannerStateChanged();
  }

  void _scheduleBannerRetry() {
    if (!kReleaseMode &&
        Platform.isAndroid == false &&
        Platform.isIOS == false) {
      return;
    }
    _bannerRetryTimer?.cancel();
    _bannerRetryTimer = Timer(const Duration(seconds: 30), () {
      _bannerRetryTimer = null;
      _loadBannerAdInternal();
    });
  }

  void _notifyBannerStateChanged() {
    bannerStateNotifier.value++;
  }
}
