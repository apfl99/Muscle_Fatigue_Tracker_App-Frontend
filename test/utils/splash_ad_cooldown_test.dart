import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_fatigue_tracker/utils/splash_ad_cooldown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashAdCooldownStore', () {
    test('초기 상태에서는 스플래시 전면 광고를 노출할 수 있다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SplashAdCooldownStore();

      final canShow = await store.canShow(
        cooldown: const Duration(minutes: 30),
      );

      expect(canShow, isTrue);
    });

    test('markShownNow 직후에는 쿨타임 동안 노출하지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SplashAdCooldownStore();
      await store.markShownNow();

      final canShow = await store.canShow(
        cooldown: const Duration(minutes: 30),
      );

      expect(canShow, isFalse);
    });

    test('쿨타임이 경과하면 다시 노출할 수 있다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final store = SplashAdCooldownStore(
        sharedPreferences: prefs,
        clock: () => now,
      );
      await store.markShownNow();

      final blocked = await store.canShow(
        cooldown: const Duration(minutes: 30),
      );
      expect(blocked, isFalse);

      now = now.add(const Duration(minutes: 31));
      final canShow = await store.canShow(
        cooldown: const Duration(minutes: 30),
      );
      expect(canShow, isTrue);
    });
  });
}
