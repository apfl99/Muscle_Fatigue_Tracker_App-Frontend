import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/ad_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAndShowAd();
  }

  Future<void> _initializeAndShowAd() async {
    final adManager = AdManager.instance;

    try {
      // AdMob 초기화 및 광고 로드
      print('📱 AdMob 초기화 시작...');
      await adManager.initialize();
      print('✅ AdMob 초기화 완료');

      // Interstitial 광고가 준비될 때까지 대기 (최대 5초)
      int waitCount = 0;
      while (!adManager.isInterstitialAdReady && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
        if (waitCount % 10 == 0) {
          print('⏳ 광고 로드 대기 중... (${waitCount * 100}ms)');
        }
      }

      if (adManager.isInterstitialAdReady) {
        print('✅ 전면 광고 준비 완료, 표시 시도');

        // 전면 광고 표시 시도 (show는 void를 반환하므로 콜백에서 처리)
        adManager.showInterstitialAd(
          onClosed: () {
            print('📺 전면 광고 닫힘, 메인 화면으로 이동');
            if (mounted) {
              _navigateToHome();
            }
          },
        );

        // 광고가 표시되면 콜백에서 처리되므로 여기서는 대기
        // 광고가 표시되지 않으면 아래 코드로 진행
        await Future.delayed(const Duration(seconds: 1));
      } else {
        print('⚠️ 전면 광고가 준비되지 않음, 스킵');
      }
    } catch (e) {
      print('❌ 광고 초기화 오류: $e');
    }

    // 광고 표시 여부와 관계없이 최소 2초 후 메인 화면으로 이동
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      print('🏠 메인 화면으로 이동');
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const SensorDataPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Container(
          color: AppTheme.darkBackground,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 앱 아이콘
                Image.asset(
                  'assets/images/icon.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 40),
                // 앱 이름
                Text(
                  'Muscle Care',
                  style: GoogleFonts.poppins(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '근피로도 웰니스 분석',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '스마트폰 센서 기반 참고 지표',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white54,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 60),
                // 로딩 인디케이터
                const SizedBox(
                  width: 40,
                  height: 40,
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
      ),
    );
  }
}
