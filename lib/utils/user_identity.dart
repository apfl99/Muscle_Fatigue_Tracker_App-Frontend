import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';

class UserIdentity {
  UserIdentity._();

  static const String _prefsKey = 'device_user_id';
  static final UserIdentity instance = UserIdentity._();

  String? _cachedId;
  String? _lastMigratedFrom;

  Future<void> ensureInitialized() async {
    if (_cachedId != null) return;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && stored.isNotEmpty) {
      final sanitized = _sanitizeId(stored);
      if (sanitized != stored) {
        _lastMigratedFrom = stored;
        _cachedId = sanitized;
        await prefs.setString(_prefsKey, sanitized);
      } else {
        _cachedId = sanitized;
      }
      return;
    }

    final generated = await _generateDeviceId();
    _cachedId = generated;
    await prefs.setString(_prefsKey, generated);
  }

  Future<String> get userId async {
    await ensureInitialized();
    return _cachedId!;
  }

  String? get lastMigratedFrom => _lastMigratedFrom;

  Future<String> _generateDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final id = _sanitizeId(info.id);
        if (id.isNotEmpty) {
          return 'android_$id';
        }
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final raw = info.identifierForVendor;
        final id = raw != null ? _sanitizeId(raw) : null;
        if (id != null && id.isNotEmpty) {
          return 'ios_$id';
        }
      }
    } catch (e) {
      appLog('⚠️ 디바이스 ID 조회 실패: $e');
    }
    final uuid = const Uuid().v4().replaceAll('-', '');
    return 'uuid_$uuid';
  }

  String _sanitizeId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^\w\.]'), '');
    if (sanitized.isEmpty) return value.replaceAll('-', '');
    return sanitized;
  }
}
