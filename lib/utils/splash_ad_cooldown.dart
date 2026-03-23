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
    final prefs = await _prefs();
    final lastShownAtMs = prefs.getInt(_lastShownAtKey);
    if (lastShownAtMs == null) {
      return true;
    }

    final lastShownAt = DateTime.fromMillisecondsSinceEpoch(lastShownAtMs);
    final elapsed = _clock().difference(lastShownAt);
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
