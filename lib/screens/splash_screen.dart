import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ad_manager.dart';
import 'main_home_page.dart';

abstract class SplashAdController {
  Future<void> initialize();
  bool get isInterstitialReady;
  void showInterstitial({required VoidCallback onClosed});
}

class AdManagerSplashController implements SplashAdController {
  AdManagerSplashController({AdManager? adManager})
      : _adManager = adManager ?? AdManager.instance;

  final AdManager _adManager;

  @override
  Future<void> initialize() => _adManager.initialize();

  @override
  bool get isInterstitialReady => _adManager.isInterstitialAdReady;

  @override
  void showInterstitial({required VoidCallback onClosed}) {
    _adManager.showInterstitialAd(onClosed: onClosed);
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.minimumSplashDuration = const Duration(milliseconds: 2500),
    this.adLoadTimeout = const Duration(seconds: 3),
    this.homeBuilder,
    this.adController,
  });

  final Duration minimumSplashDuration;
  final Duration adLoadTimeout;
  final WidgetBuilder? homeBuilder;
  final SplashAdController? adController;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _runSplashFlow();
  }

  Future<void> _runSplashFlow() async {
    final adController = widget.adController ??
        AdManagerSplashController(adManager: AdManager.instance);

    unawaited(_warmupHomeData());
    unawaited(adController.initialize());
    await Future<void>.delayed(widget.minimumSplashDuration);

    if (!mounted || _navigated) {
      return;
    }

    if (adController.isInterstitialReady) {
      await _showInterstitialAndWaitClose(adController);
    } else {
      // 최소 스플래시 시간 이후에도 광고가 준비되지 않았다면 지연 없이 홈으로 이동한다.
      // (네트워크 실패/광고 로드 실패 포함)
      _navigateToHome();
      return;
    }

    if (!mounted || _navigated) {
      return;
    }
    _navigateToHome();
  }

  Future<void> _warmupHomeData() async {
    try {
      await context.read<HeatmapProvider>().initialize();
    } catch (_) {
      // 워밍업 실패 시에도 스플래시 흐름은 계속 진행한다.
    }
  }

  Future<void> _showInterstitialAndWaitClose(
    SplashAdController adController,
  ) async {
    final closedCompleter = Completer<void>();

    adController.showInterstitial(
      onClosed: () {
        if (!closedCompleter.isCompleted) {
          closedCompleter.complete();
        }
      },
    );

    await closedCompleter.future.timeout(
      widget.adLoadTimeout,
      onTimeout: () {},
    );
  }

  void _navigateToHome() {
    if (!mounted || _navigated) {
      return;
    }
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: widget.homeBuilder ?? (_) => const MainHomePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/icon.png',
                width: 110,
                height: 110,
                fit: BoxFit.cover,
              ),
              const SizedBox(height: 32),
              Text(
                'Muscle Care',
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '운동 수행 패턴 분석',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: Colors.white70,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
