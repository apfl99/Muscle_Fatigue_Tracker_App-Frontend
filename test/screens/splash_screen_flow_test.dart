import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_fatigue_tracker/providers/heatmap_provider.dart';
import 'package:muscle_fatigue_tracker/screens/splash_screen.dart';
import 'package:muscle_fatigue_tracker/utils/splash_ad_cooldown.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashScreen 런칭 플로우', () {
    testWidgets('광고 준비 시 스플래시 전면 광고를 노출한다', (tester) async {
      final adController = _FakeSplashAdController(readyAfterPreloadCalls: 0);

      await tester.pumpWidget(
        ChangeNotifierProvider<HeatmapProvider>(
          create: (_) => _NoopHeatmapProvider(),
          child: MaterialApp(
            home: SplashScreen(
              minimumSplashDuration: Duration.zero,
              adLoadTimeout: const Duration(milliseconds: 50),
              adController: adController,
              adCooldownStore: _FixedCooldownStore(canShowResult: true),
              homeBuilder: (_) => const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(adController.showCount, 1);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('광고 미준비 시 타임아웃 후 홈으로 이동한다', (tester) async {
      final adController = _FakeSplashAdController(readyAfterPreloadCalls: 999);

      await tester.pumpWidget(
        ChangeNotifierProvider<HeatmapProvider>(
          create: (_) => _NoopHeatmapProvider(),
          child: MaterialApp(
            home: SplashScreen(
              minimumSplashDuration: Duration.zero,
              adLoadTimeout: const Duration(milliseconds: 50),
              adController: adController,
              adCooldownStore: _FixedCooldownStore(canShowResult: true),
              homeBuilder: (_) => const Scaffold(body: Text('home')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(adController.showCount, 0);
      expect(find.text('home'), findsOneWidget);
    });
  });
}

class _NoopHeatmapProvider extends HeatmapProvider {
  @override
  Future<void> initialize() async {}
}

class _FakeSplashAdController implements SplashAdController {
  _FakeSplashAdController({
    required this.readyAfterPreloadCalls,
  });

  final int readyAfterPreloadCalls;
  int showCount = 0;
  int preloadCount = 0;

  @override
  Future<void> initialize() async {
    if (readyAfterPreloadCalls == 0) {
      preloadCount = 0;
    }
  }

  @override
  bool get isInterstitialReady => preloadCount >= readyAfterPreloadCalls;

  @override
  void loadInterstitial() {
    preloadCount += 1;
  }

  @override
  void showInterstitial({required VoidCallback onClosed}) {
    showCount += 1;
    onClosed();
  }
}

class _FixedCooldownStore extends SplashAdCooldownStore {
  _FixedCooldownStore({required this.canShowResult});

  final bool canShowResult;

  @override
  Future<bool> canShow({required Duration cooldown}) async => canShowResult;

  @override
  Future<void> markShownNow() async {}
}
