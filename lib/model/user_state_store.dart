import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import 'baseline.dart';

/// UserState를 단일 소스로 관리하는 Store (SQLite → UI one-way)
class UserStateStore {
  UserStateStore._();
  static final UserStateStore instance = UserStateStore._();

  /// DB user_state 그대로 보관 (null 가능)
  final ValueNotifier<Map<String, dynamic>?> state = ValueNotifier(null);

  bool get hasBaseline {
    final s = state.value;
    if (s == null) return false;
    final rms = s['rms_base'] as num?;
    final freq = s['freq_base'] as num?;
    return rms != null && freq != null;
  }

  Future<void> refreshFromDb() async {
    final s = await DatabaseHelper.instance.getUserState();
    state.value = s;
  }

  /// 기준값 저장(EMA 계산된 결과 Map) → DB 저장 후 메모리 동기화
  Future<void> saveBaseline(Map<String, dynamic> baselineData) async {
    await DatabaseHelper.instance.saveBaseline(baselineData);
    // BaselineManager도 최신화(기존 코드와의 호환)
    await BaselineManager.instance.initialize();
    await BaselineManager.instance.syncWithDatabase();
    await refreshFromDb();
  }

  /// 기준값 초기화(DB null) → 메모리 동기화
  Future<void> clearBaseline() async {
    await DatabaseHelper.instance.clearBaseline();
    await BaselineManager.instance.initialize();
    await BaselineManager.instance.syncWithDatabase();
    await refreshFromDb();
  }
}
