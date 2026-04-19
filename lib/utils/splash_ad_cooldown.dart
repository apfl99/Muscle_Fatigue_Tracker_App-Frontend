import 'package:shared_preferences/shared_preferences.dart';

class SplashAdCooldownStore {
  SplashAdCooldownStore({
    SharedPreferences? sharedPreferences,
    DateTime Function()? clock,
  })  : _sharedPreferences = sharedPreferences,
        _clock = clock ?? DateTime.now;

  static const String _lastShownAtKey = 'ads.splash.last_shown_at_ms';

  SharedPreferences? _sharedPreferences;
  final DateTime Function() _clock;

  Future<bool> canShow({
    required Duration cooldown,
  }) async {
    if (cooldown <= Duration.zero) {
      return true;
    }
    final prefs = await _prefs();
    final lastShownAtMs = prefs.getInt(_lastShownAtKey);
    if (lastShownAtMs == null) {
      return true;
    }

    final lastShownAt = DateTime.fromMillisecondsSinceEpoch(lastShownAtMs);
    final now = _clock();
    if (lastShownAt.isAfter(now)) {
      // 디바이스 시간 변경 등 비정상 값은 즉시 보정한다.
      await prefs.setInt(_lastShownAtKey, now.millisecondsSinceEpoch);
      return true;
    }
    final elapsed = now.difference(lastShownAt);
    return elapsed >= cooldown;
  }

  Future<void> markShownNow() async {
    final prefs = await _prefs();
    await prefs.setInt(_lastShownAtKey, _clock().millisecondsSinceEpoch);
  }

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }
}
