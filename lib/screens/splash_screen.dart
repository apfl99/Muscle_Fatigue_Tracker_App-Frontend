import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ad_manager.dart';
import '../utils/splash_ad_cooldown.dart';
import 'main_home_page.dart';

abstract class SplashAdController {
  Future<void> initialize();
  bool get isInterstitialReady;
  void loadInterstitial();
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
  void loadInterstitial() {
    _adManager.loadInterstitialAd(force: true);
  }

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
    this.adDisplayTimeout = const Duration(seconds: 6),
    this.adCooldown = const Duration(minutes: 30),
    this.homeBuilder,
    this.adController,
    this.adCooldownStore,
  });

  final Duration minimumSplashDuration;
  final Duration adLoadTimeout;
  final Duration adDisplayTimeout;
  final Duration adCooldown;
  final WidgetBuilder? homeBuilder;
  final SplashAdController? adController;
  final SplashAdCooldownStore? adCooldownStore;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _runSplashFlow();
    });
  }

  Future<void> _runSplashFlow() async {
    final adController = widget.adController ??
        AdManagerSplashController(adManager: AdManager.instance);
    final adCooldownStore = widget.adCooldownStore ?? SplashAdCooldownStore();

    unawaited(_warmupHomeData());
    final canShowAd = await adCooldownStore.canShow(
      cooldown: widget.adCooldown,
    );
    if (!mounted || _navigated) {
      return;
    }
    if (!canShowAd) {
      _navigateToHome();
      return;
    }

    final adInitFuture = adController.initialize();
    await Future<void>.delayed(widget.minimumSplashDuration);
    await adInitFuture.timeout(widget.adLoadTimeout, onTimeout: () {});

    if (!mounted || _navigated) {
      return;
    }

    await _waitUntilInterstitialReady(adController: adController);
    final didShowAd = await _showInterstitialAndWaitClose(adController);
    if (didShowAd) {
      await adCooldownStore.markShownNow();
    }

    if (!mounted || _navigated) {
      return;
    }
    _navigateToHome();
  }

  Future<void> _waitUntilInterstitialReady({
    required SplashAdController adController,
  }) async {
    if (adController.isInterstitialReady) {
      return;
    }

    final deadline = DateTime.now().add(widget.adLoadTimeout);
    while (mounted &&
        !adController.isInterstitialReady &&
        DateTime.now().isBefore(deadline)) {
      adController.loadInterstitial();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _warmupHomeData() async {
    try {
      await context.read<HeatmapProvider>().initialize();
    } catch (_) {
      // 워밍업 실패 시에도 스플래시 흐름은 계속 진행한다.
    }
  }

  Future<bool> _showInterstitialAndWaitClose(
    SplashAdController adController,
  ) async {
    if (!adController.isInterstitialReady) {
      return false;
    }

    final closedCompleter = Completer<void>();

    adController.showInterstitial(
      onClosed: () {
        if (!closedCompleter.isCompleted) {
          closedCompleter.complete();
        }
      },
    );

    await closedCompleter.future.timeout(
      widget.adDisplayTimeout,
      onTimeout: () {},
    );
    return true;
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

  String _resolvedTagline(BuildContext context) {
    // Widget tests may render this screen without EasyLocalization.
    if (EasyLocalization.of(context) == null) {
      return 'Movement Pattern Recording';
    }
    return 'splash.tagline'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textHigh,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _resolvedTagline(context),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textMedium,
                          letterSpacing: 0.0,
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
          },
        ),
      ),
    );
  }
}
