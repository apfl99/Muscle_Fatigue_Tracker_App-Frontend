import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert';
import '../worker/worker_manager.dart';
import 'dart:async';
import 'user_stats.dart';

/// 통합 데이터베이스 헬퍼 클래스
/// DB_SCHEMA.md (v1.0.0) 기반으로 전체 DB 관리
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static bool _isInitializing = false;

  DatabaseHelper._init();

  static const String dbName = 'fatigue_tracker.db';
  static const int dbVersion = 5;

  // 테이블 이름 (DB_SCHEMA.md 기준)
  static const String tableUserState = 'user_state';
  static const String tableFatigueDataset = 'fatigue_dataset';
  static const String tableModelVersions = 'model_versions';
  static const String tableSyncHistory = 'sync_history';

  static const String defaultUserId = 'local_user';

  Future<Database> get database async {
    if (_database != null) return _database!;

    // 이미 초기화 중이면 대기
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    if (_database != null) return _database!;

    _isInitializing = true;
    try {
      _database = await _initDB();
      return _database!;
    } finally {
      _isInitializing = false;
    }
  }

  Future<Database> _initDB() async {
    try {
      print('🗄️ 데이터베이스 초기화 시작...');
      print('📱 플랫폼: ${Platform.operatingSystem}');

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, dbName);

      print('📂 DB 경로: $path');

      // 데이터베이스 열기
      final db = await openDatabase(
        path,
        version: dbVersion,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          print('✅ 데이터베이스 열림');
        },
      );

      print('✅ 데이터베이스 초기화 완료');
      return db;
    } catch (e, stackTrace) {
      print('❌ DB 초기화 오류: $e');
      print('스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    print('🔨 테이블 생성 중 (SQLite 스키마)...');

    // 1. user_state 테이블 (개인화 설정 저장)
    await db.execute('''
    CREATE TABLE IF NOT EXISTS $tableUserState (
      user_id TEXT PRIMARY KEY,
      rms_base REAL,
      freq_base REAL,
      user_emb TEXT,
      model_version TEXT,
      last_sync TEXT
    )
    ''');
    print('✅ user_state 테이블 생성 완료');

    // 초기 user_state 레코드 삽입 (baseline은 미설정 상태 유지)
    await db.insert(
      tableUserState,
      {
        'user_id': defaultUserId,
        'user_emb': jsonEncode([
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
        ]), // 12D 벡터
        'model_version': '1.0.0',
        'last_sync': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    print('✅ user_state 초기 레코드 삽입 완료');

    // 2. fatigue_dataset 테이블 (윈도우 단위 데이터셋)
    await db.execute('''
    CREATE TABLE IF NOT EXISTS $tableFatigueDataset (
      user_id TEXT NOT NULL,
      session_id TEXT NOT NULL,
      window_id INTEGER NOT NULL,
      window_start_ms INTEGER NOT NULL,
      window_end_ms INTEGER NOT NULL,
      timestamp_utc TEXT,
      acc_x_mean REAL,
      acc_y_mean REAL,
      acc_z_mean REAL,
      gyro_x_mean REAL,
      gyro_y_mean REAL,
      gyro_z_mean REAL,
      linacc_x_mean REAL,
      linacc_y_mean REAL,
      linacc_z_mean REAL,
      gravity_x_mean REAL,
      gravity_y_mean REAL,
      gravity_z_mean REAL,
      acc_x_std REAL,
      acc_y_std REAL,
      acc_z_std REAL,
      gyro_x_std REAL,
      gyro_y_std REAL,
      gyro_z_std REAL,
      rms_acc REAL,
      rms_gyro REAL,
      mean_freq_acc REAL,
      mean_freq_gyro REAL,
      entropy_acc REAL,
      entropy_gyro REAL,
      jerk_mean REAL,
      jerk_std REAL,
      stability_index REAL,
      rms_base REAL,
      freq_base REAL,
      user_emb TEXT,
      fatigue_prev REAL,
      fatigue REAL,
      fatigue_level INTEGER,
      quality_flag INTEGER DEFAULT 1,
      window_size_ms INTEGER DEFAULT 2000,
      overlap_rate REAL DEFAULT 0.5,
      mode TEXT,
      synced INTEGER DEFAULT 0,
      PRIMARY KEY (user_id, session_id, window_id)
    )
    ''');
    print('✅ fatigue_dataset 테이블 생성 완료');

    // 인덱스 생성
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dataset_user ON $tableFatigueDataset(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dataset_session ON $tableFatigueDataset(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dataset_synced ON $tableFatigueDataset(synced)',
    );
    print('✅ fatigue_dataset 인덱스 생성 완료');

    // 3. model_versions 테이블
    await db.execute('''
    CREATE TABLE IF NOT EXISTS $tableModelVersions (
      model_type TEXT PRIMARY KEY,
      version TEXT,
      path TEXT,
      updated_at TEXT NOT NULL
    )
    ''');
    print('✅ model_versions 테이블 생성 완료');

    // 초기 모델 버전 레코드
    final nowIso = DateTime.now().toIso8601String();
    await db.insert(
      tableModelVersions,
      {
        'model_type': 'EMA',
        'version': '1.0.0',
        'path': 'local',
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      tableModelVersions,
      {
        'model_type': 'Hybrid',
        'version': '1.0.0',
        'path': 'local',
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      tableModelVersions,
      {
        'model_type': 'E2E',
        'version': '1.0.0',
        'path': 'local',
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    print('✅ model_versions 초기 레코드 삽입 완료');

    // 4. sync_history 테이블
    await db.execute('''
    CREATE TABLE IF NOT EXISTS $tableSyncHistory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      sync_type TEXT NOT NULL,
      status TEXT NOT NULL,
      executed_at TEXT NOT NULL
    )
    ''');
    print('✅ sync_history 테이블 생성 완료');
    print('✅ 모든 테이블 생성 완료');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 데이터베이스 업그레이드 중... ($oldVersion → $newVersion)');

    if (oldVersion < 4) {
      print('🧹 v4 스키마로 마이그레이션: 기존 fatigue_logs 및 관련 테이블 정리');

      await db.execute('DROP TABLE IF EXISTS users');
      await db.execute('DROP TABLE IF EXISTS fatigue_logs');
      await db.execute('DROP TABLE IF EXISTS temp_measurements');
      await db.execute('DROP INDEX IF EXISTS idx_logs_user');
      await db.execute('DROP INDEX IF EXISTS idx_logs_date');

      // 새로운 스키마 생성
      await _createDB(db, newVersion);

      print('✅ v4 스키마 마이그레이션 완료');
    }

    if (oldVersion < 5) {
      print('🧹 v5 스키마로 마이그레이션: fatigue_dataset 기본키 재구성');
      await db.execute('DROP TABLE IF EXISTS $tableFatigueDataset');
      await db.execute('DROP INDEX IF EXISTS idx_dataset_user');
      await db.execute('DROP INDEX IF EXISTS idx_dataset_session');
      await db.execute('DROP INDEX IF EXISTS idx_dataset_synced');
      await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableFatigueDataset (
        user_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        window_id INTEGER NOT NULL,
        window_start_ms INTEGER NOT NULL,
        window_end_ms INTEGER NOT NULL,
        timestamp_utc TEXT,
        acc_x_mean REAL,
        acc_y_mean REAL,
        acc_z_mean REAL,
        gyro_x_mean REAL,
        gyro_y_mean REAL,
        gyro_z_mean REAL,
        linacc_x_mean REAL,
        linacc_y_mean REAL,
        linacc_z_mean REAL,
        gravity_x_mean REAL,
        gravity_y_mean REAL,
        gravity_z_mean REAL,
        acc_x_std REAL,
        acc_y_std REAL,
        acc_z_std REAL,
        gyro_x_std REAL,
        gyro_y_std REAL,
        gyro_z_std REAL,
        rms_acc REAL,
        rms_gyro REAL,
        mean_freq_acc REAL,
        mean_freq_gyro REAL,
        entropy_acc REAL,
        entropy_gyro REAL,
        jerk_mean REAL,
        jerk_std REAL,
        stability_index REAL,
        rms_base REAL,
        freq_base REAL,
        user_emb TEXT,
        fatigue_prev REAL,
        fatigue REAL,
        fatigue_level INTEGER,
        quality_flag INTEGER DEFAULT 1,
        window_size_ms INTEGER DEFAULT 2000,
        overlap_rate REAL DEFAULT 0.5,
        mode TEXT,
        synced INTEGER DEFAULT 0,
        PRIMARY KEY (user_id, session_id, window_id)
      )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dataset_user ON $tableFatigueDataset(user_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dataset_session ON $tableFatigueDataset(session_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dataset_synced ON $tableFatigueDataset(synced)',
      );
      print('✅ v5 스키마 마이그레이션 완료 (id 컬럼 제거)');
    }
  }

  /// ========================================
  /// User State 관련 메서드 (baseline + user_emb)
  /// ========================================

  Future<Map<String, dynamic>?> getUserState({
    String userId = defaultUserId,
  }) async {
    final db = await database;
    final result = await db.query(
      tableUserState,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> updateUserState({
    String userId = defaultUserId,
    double? rmsBase,
    double? freqBase,
    List<double>? userEmb,
    String? modelVersion,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    final existing = await getUserState(userId: userId);

    final data = <String, dynamic>{
      'user_id': userId,
      'last_sync': nowIso,
    };
    if (rmsBase != null) data['rms_base'] = rmsBase;
    if (freqBase != null) data['freq_base'] = freqBase;
    if (userEmb != null) data['user_emb'] = jsonEncode(userEmb);
    if (modelVersion != null) data['model_version'] = modelVersion;

    if (existing == null) {
      // 레코드 없으면 새로 생성 (UPSERT)
      await db.insert(
        tableUserState,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      // 있으면 업데이트
      final updateData = Map<String, dynamic>.from(data);
      updateData.remove('user_id');
      await db.update(
        tableUserState,
        updateData,
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    }
  }

  Future<List<double>> getUserEmbedding({String userId = defaultUserId}) async {
    final state = await getUserState(userId: userId);
    if (state == null || state['user_emb'] == null) {
      return List.filled(12, 0.0);
    }
    final embList = jsonDecode(state['user_emb'] as String) as List;
    return embList.map((e) => (e as num).toDouble()).toList();
  }

  /// ========================================
  /// Fatigue Logs 관련 메서드
  /// ========================================

  Future<void> insertFatigueWindows({
    String userId = defaultUserId,
    required String sessionId,
    required List<Map<String, dynamic>> windows,
    String? mode,
    double? rmsBaseOverride,
    double? freqBaseOverride,
    List<double>? userEmbOverride,
  }) async {
    if (windows.isEmpty) {
      print('⚠️ 저장할 윈도우 데이터가 없습니다 (sessionId: $sessionId)');
      return;
    }

    final db = await database;

    final userState = await getUserState(userId: userId);
    final userEmbData =
        userEmbOverride ?? await getUserEmbedding(userId: userId);
    final userEmbList =
        userEmbData.isNotEmpty ? userEmbData : List<double>.filled(12, 0.0);
    final rmsBase =
        rmsBaseOverride ?? (userState?['rms_base'] as num?)?.toDouble() ?? 0.0;
    final freqBase = freqBaseOverride ??
        (userState?['freq_base'] as num?)?.toDouble() ??
        0.0;

    final batch = db.batch();
    for (final window in windows) {
      final windowId = window['window_id'] ?? window['window_index'];
      final windowStart = window['window_start_ms'];
      final windowEnd = window['window_end_ms'];

      if (windowId == null || windowStart == null || windowEnd == null) {
        print('⚠️ 윈도우 필수 값이 누락되어 저장을 건너뜁니다: $window');
        continue;
      }

      final row = <String, dynamic>{
        'user_id': userId,
        'session_id': sessionId,
        'window_id': windowId,
        'window_start_ms': windowStart,
        'window_end_ms': windowEnd,
        'timestamp_utc': (window['timestamp_utc'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        'acc_x_mean': (window['acc_x_mean'] as num?)?.toDouble() ?? 0.0,
        'acc_y_mean': (window['acc_y_mean'] as num?)?.toDouble() ?? 0.0,
        'acc_z_mean': (window['acc_z_mean'] as num?)?.toDouble() ?? 0.0,
        'gyro_x_mean': (window['gyro_x_mean'] as num?)?.toDouble() ?? 0.0,
        'gyro_y_mean': (window['gyro_y_mean'] as num?)?.toDouble() ?? 0.0,
        'gyro_z_mean': (window['gyro_z_mean'] as num?)?.toDouble() ?? 0.0,
        'linacc_x_mean': (window['linacc_x_mean'] as num?)?.toDouble() ?? 0.0,
        'linacc_y_mean': (window['linacc_y_mean'] as num?)?.toDouble() ?? 0.0,
        'linacc_z_mean': (window['linacc_z_mean'] as num?)?.toDouble() ?? 0.0,
        'gravity_x_mean': (window['gravity_x_mean'] as num?)?.toDouble() ?? 0.0,
        'gravity_y_mean': (window['gravity_y_mean'] as num?)?.toDouble() ?? 0.0,
        'gravity_z_mean': (window['gravity_z_mean'] as num?)?.toDouble() ?? 0.0,
        'acc_x_std': (window['acc_x_std'] as num?)?.toDouble() ?? 0.0,
        'acc_y_std': (window['acc_y_std'] as num?)?.toDouble() ?? 0.0,
        'acc_z_std': (window['acc_z_std'] as num?)?.toDouble() ?? 0.0,
        'gyro_x_std': (window['gyro_x_std'] as num?)?.toDouble() ?? 0.0,
        'gyro_y_std': (window['gyro_y_std'] as num?)?.toDouble() ?? 0.0,
        'gyro_z_std': (window['gyro_z_std'] as num?)?.toDouble() ?? 0.0,
        'rms_acc': (window['rms_acc'] as num?)?.toDouble() ?? 0.0,
        'rms_gyro': (window['rms_gyro'] as num?)?.toDouble() ?? 0.0,
        'mean_freq_acc': (window['mean_freq_acc'] as num?)?.toDouble() ?? 0.0,
        'mean_freq_gyro': (window['mean_freq_gyro'] as num?)?.toDouble() ?? 0.0,
        'entropy_acc': (window['entropy_acc'] as num?)?.toDouble() ?? 0.0,
        'entropy_gyro': (window['entropy_gyro'] as num?)?.toDouble() ?? 0.0,
        'jerk_mean': (window['jerk_mean'] as num?)?.toDouble() ?? 0.0,
        'jerk_std': (window['jerk_std'] as num?)?.toDouble() ?? 0.0,
        'stability_index':
            (window['stability_index'] as num?)?.toDouble() ?? 0.0,
        'rms_base': rmsBase,
        'freq_base': freqBase,
        'user_emb': jsonEncode(userEmbList),
        'fatigue_prev': (window['fatigue_prev'] as num?)?.toDouble() ?? 0.0,
        'fatigue': (window['fatigue'] as num?)?.toDouble() ?? 0.0,
        'fatigue_level': (window['fatigue_level'] as num?)?.toInt() ?? 0,
        'quality_flag': (window['quality_flag'] as num?)?.toInt() ?? 1,
        'window_size_ms': (window['window_size_ms'] as num?)?.toInt() ?? 0,
        'overlap_rate': (window['overlap_rate'] as num?)?.toDouble() ?? 0.0,
        'mode': mode ?? (window['mode'] as String? ?? 'ema'),
        'synced': (window['synced'] as num?)?.toInt() ?? 0,
      };

      batch.insert(tableFatigueDataset, row);
    }

    await batch.commit(noResult: true);
    print('✅ 피로도 윈도우 ${windows.length}개 저장 완료 (sessionId: $sessionId)');
  }

  Future<List<Map<String, dynamic>>> getAllFatigueLogs({
    String userId = defaultUserId,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 
        session_id,
        MIN(window_start_ms) AS first_window_start_ms,
        MAX(window_end_ms) AS last_window_end_ms,
        MAX(timestamp_utc) AS timestamp_utc,
        COUNT(*) AS window_count,
        AVG(rms_acc) AS rms,
        AVG(mean_freq_acc) AS freq,
        AVG(fatigue) AS fatigue,
        MAX(mode) AS mode,
        MIN(synced) AS synced
      FROM $tableFatigueDataset
      WHERE user_id = ?
      GROUP BY session_id
      ORDER BY last_window_end_ms DESC
      ''',
      [userId],
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> getRecentFatigueLogs({
    String userId = defaultUserId,
    int limit = 10,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 
        session_id,
        MIN(window_start_ms) AS first_window_start_ms,
        MAX(window_end_ms) AS last_window_end_ms,
        MAX(timestamp_utc) AS timestamp_utc,
        COUNT(*) AS window_count,
        AVG(rms_acc) AS rms,
        AVG(mean_freq_acc) AS freq,
        AVG(fatigue) AS fatigue,
        MAX(mode) AS mode,
        MIN(synced) AS synced
      FROM $tableFatigueDataset
      WHERE user_id = ?
      GROUP BY session_id
      ORDER BY last_window_end_ms DESC
      LIMIT ?
      ''',
      [userId, limit],
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> getFatigueLogsByDateRange({
    String userId = defaultUserId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await database;
    final startMs = startDate.millisecondsSinceEpoch;
    final endMs = endDate.millisecondsSinceEpoch;

    final result = await db.rawQuery(
      '''
      SELECT 
        session_id,
        MIN(window_start_ms) AS first_window_start_ms,
        MAX(window_end_ms) AS last_window_end_ms,
        MAX(timestamp_utc) AS timestamp_utc,
        COUNT(*) AS window_count,
        AVG(rms_acc) AS rms,
        AVG(mean_freq_acc) AS freq,
        AVG(fatigue) AS fatigue,
        MAX(mode) AS mode,
        MIN(synced) AS synced
      FROM $tableFatigueDataset
      WHERE user_id = ?
        AND window_start_ms >= ?
        AND window_end_ms <= ?
      GROUP BY session_id
      ORDER BY last_window_end_ms DESC
      ''',
      [userId, startMs, endMs],
    );
    return result;
  }

  Future<int> deleteFatigueLog(String sessionId) async {
    final db = await database;
    return await db.delete(
      tableFatigueDataset,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> deleteAllFatigueLogs({String userId = defaultUserId}) async {
    final db = await database;
    return await db.delete(
      tableFatigueDataset,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLogs({
    String userId = defaultUserId,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 
        session_id,
        MIN(window_start_ms) AS first_window_start_ms,
        MAX(window_end_ms) AS last_window_end_ms,
        MAX(timestamp_utc) AS timestamp_utc,
        COUNT(*) AS window_count,
        AVG(rms_acc) AS rms,
        AVG(mean_freq_acc) AS freq,
        AVG(fatigue) AS fatigue,
        MAX(mode) AS mode
      FROM $tableFatigueDataset
      WHERE user_id = ? AND synced = 0
      GROUP BY session_id
      ORDER BY first_window_start_ms ASC
      ''',
      [userId],
    );
    return result;
  }

  Future<void> markLogsAsSynced(
    List<String> sessionIds, {
    String userId = defaultUserId,
  }) async {
    final db = await database;
    for (final sessionId in sessionIds) {
      await db.update(
        tableFatigueDataset,
        {'synced': 1},
        where: 'session_id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
    }
    print('✅ ${sessionIds.length}개 로그 동기화 완료 표시');
  }

  Future<List<Map<String, dynamic>>> getWindowsBySession(
    String sessionId, {
    String userId = defaultUserId,
    bool onlyUnsynced = false,
  }) async {
    final db = await database;
    final whereBuffer = StringBuffer('session_id = ? AND user_id = ?');
    final whereArgs = <dynamic>[sessionId, userId];
    if (onlyUnsynced) {
      whereBuffer.write(' AND (synced IS NULL OR synced = 0)');
    }
    return await db.query(
      tableFatigueDataset,
      where: whereBuffer.toString(),
      whereArgs: whereArgs,
      orderBy: 'window_id ASC',
    );
  }

  Future<bool> hasUnsyncedWindows(
    String sessionId, {
    String userId = defaultUserId,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS cnt
      FROM $tableFatigueDataset
      WHERE user_id = ? AND session_id = ? AND (synced IS NULL OR synced = 0)
      ''',
      [userId, sessionId],
    );
    final count = (result.isNotEmpty ? result.first['cnt'] : 0) as int? ?? 0;
    return count > 0;
  }

  /// ========================================
  /// Model Versions 관련 메서드
  /// ========================================

  Future<Map<String, dynamic>?> getModelVersion(String modelType) async {
    final db = await database;
    final result = await db.query(
      tableModelVersions,
      where: 'model_type = ?',
      whereArgs: [modelType],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> updateModelVersion({
    required String modelType,
    required String version,
    required String path,
  }) async {
    final db = await database;
    await db.update(
      tableModelVersions,
      {
        'version': version,
        'path': path,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'model_type = ?',
      whereArgs: [modelType],
    );
  }

  Future<List<Map<String, dynamic>>> getAllModelVersions() async {
    final db = await database;
    return await db.query(tableModelVersions);
  }

  /// ========================================
  /// Sync History 관련 메서드
  /// ========================================

  Future<int> insertSyncHistory({
    String userId = defaultUserId,
    required String syncType,
    required String status,
  }) async {
    final db = await database;

    final data = {
      'user_id': userId,
      'sync_type': syncType,
      'status': status,
      'executed_at': DateTime.now().toIso8601String(),
    };

    return await db.insert(tableSyncHistory, data);
  }

  Future<List<Map<String, dynamic>>> getSyncHistory({
    String userId = defaultUserId,
    int limit = 20,
  }) async {
    final db = await database;
    return await db.query(
      tableSyncHistory,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'executed_at DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLastSync({
    String userId = defaultUserId,
    required String syncType,
  }) async {
    final db = await database;
    final result = await db.query(
      tableSyncHistory,
      where: 'user_id = ? AND sync_type = ?',
      whereArgs: [userId, syncType],
      orderBy: 'executed_at DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// ========================================
  /// 통계 및 유틸리티
  /// ========================================

  Future<Map<String, dynamic>> getOverallStats({
    String userId = defaultUserId,
  }) async {
    final db = await database;

    // 세션 단위 요약
    final logStats = await db.rawQuery(
      '''
      WITH session_summary AS (
        SELECT 
          session_id,
          AVG(fatigue) AS fatigue,
          AVG(rms_acc) AS rms,
          AVG(mean_freq_acc) AS freq
        FROM $tableFatigueDataset
        WHERE user_id = ?
        GROUP BY session_id
      )
      SELECT 
        COUNT(*) as total_sessions,
        AVG(fatigue) as avg_fatigue,
        MIN(fatigue) as min_fatigue,
        MAX(fatigue) as max_fatigue,
        AVG(rms) as avg_rms,
        AVG(freq) as avg_freq
      FROM session_summary
    ''',
      [userId],
    );

    // 오늘 측정 수
    final today = DateTime.now();
    final startOfDay =
        DateTime(today.year, today.month, today.day).millisecondsSinceEpoch;
    final endOfDay = startOfDay + const Duration(days: 1).inMilliseconds - 1;

    final todayCount = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM (
        SELECT session_id
        FROM $tableFatigueDataset
        WHERE user_id = ?
          AND window_start_ms BETWEEN ? AND ?
        GROUP BY session_id
      )
    ''',
      [userId, startOfDay, endOfDay],
    );

    // 최근 7일 평균
    final weekAgo = today.subtract(const Duration(days: 7));
    final weekAgoMs = DateTime(weekAgo.year, weekAgo.month, weekAgo.day)
        .millisecondsSinceEpoch;

    final weekStats = await db.rawQuery(
      '''
      WITH session_summary AS (
        SELECT 
          session_id,
          MIN(window_start_ms) AS first_window_start_ms,
          AVG(fatigue) AS fatigue
        FROM $tableFatigueDataset
        WHERE user_id = ?
        GROUP BY session_id
      )
      SELECT AVG(fatigue) as week_avg_fatigue
      FROM session_summary
      WHERE first_window_start_ms >= ?
    ''',
      [userId, weekAgoMs],
    );

    return {
      'total_logs': logStats.first['total_sessions'] ?? 0,
      'avg_fatigue': logStats.first['avg_fatigue'] ?? 1.0,
      'min_fatigue': logStats.first['min_fatigue'] ?? 1.0,
      'max_fatigue': logStats.first['max_fatigue'] ?? 1.0,
      'avg_rms': logStats.first['avg_rms'] ?? 0.0,
      'avg_freq': logStats.first['avg_freq'] ?? 0.0,
      'today_logs': todayCount.first['count'] ?? 0,
      'week_avg_fatigue': weekStats.first['week_avg_fatigue'] ?? 1.0,
    };
  }

  /// 최근 N회 측정 기준으로 baseline 재계산 (EMA 방식)
  Future<void> recalculateBaseline({
    String userId = defaultUserId,
    int n = 5,
  }) async {
    final logs = await getRecentFatigueLogs(userId: userId, limit: n);

    if (logs.isEmpty) {
      print('⚠️ 피로도 로그가 없어서 baseline을 재계산할 수 없습니다');
      return;
    }

    final rmsValues = logs.map((l) => l['rms'] as double? ?? 0.0).toList();
    final freqValues = logs.map((l) => l['freq'] as double? ?? 0.0).toList();

    final rmsMean = _mean(rmsValues);
    final freqMean = _mean(freqValues);

    await updateUserState(
      userId: userId,
      rmsBase: rmsMean,
      freqBase: freqMean,
    );

    print('✅ baseline 재계산 완료: RMS=$rmsMean, Freq=$freqMean (N=${logs.length})');
  }

  /// User Embedding 계산 및 업데이트
  Future<void> calculateAndUpdateUserEmbedding({
    String userId = defaultUserId,
  }) async {
    try {
      print('🧮 User Embedding 계산 시작...');

      // 모든 피로도 로그 조회
      final allLogs = await getAllFatigueLogs(userId: userId);

      if (allLogs.isEmpty) {
        print('⚠️ 피로도 로그가 없어서 user_emb를 계산할 수 없습니다');
        return;
      }

      // UserStats 계산을 위한 데이터 준비
      final rmsValues = allLogs.map((l) => l['rms'] as double? ?? 0.0).toList();
      final freqValues =
          allLogs.map((l) => l['freq'] as double? ?? 0.0).toList();
      final fatigueValues =
          allLogs.map((l) => l['fatigue'] as double? ?? 1.0).toList();

      // 통계 계산
      final rmsMean = _mean(rmsValues);
      final freqMean = _mean(freqValues);
      final fatigueMean = _mean(fatigueValues);

      final rmsVar = _variance(rmsValues, rmsMean);
      final freqVar = _variance(freqValues, freqMean);
      final fatigueCv = fatigueMean > 0
          ? _variance(fatigueValues, fatigueMean) / fatigueMean
          : 0.0;

      // Drift 계산 (첫 번째와 마지막 값의 차이)
      final driftRms =
          allLogs.length > 1 ? (rmsValues.last - rmsValues.first).abs() : 0.0;
      final driftFreq =
          allLogs.length > 1 ? (freqValues.last - freqValues.first).abs() : 0.0;

      // 시간대별 평균 (현재는 단순화)
      const timeOfDayMean = 12.0; // 정오 기준

      // 세션 길이 평균 (현재는 단순화)
      const sessionLenMean = 5.0; // 기본 5분

      // UserStats 객체 생성
      final userStats = UserStats(
        sampleWindow: 5,
        measCount: allLogs.length,
        rmsMean: rmsMean,
        freqMean: freqMean,
        rmsVar: rmsVar,
        freqVar: freqVar,
        fatigueMean: fatigueMean,
        fatigueCv: fatigueCv,
        driftRms: driftRms,
        driftFreq: driftFreq,
        timeOfDayMean: timeOfDayMean,
        sessionLenMean: sessionLenMean,
        updatedAt: DateTime.now(),
      );

      // User Embedding 계산
      final userEmb = userStats.toUserEmbedding(rmsMean, freqMean);

      print('📊 User Embedding 계산 완료:');
      print('   - 측정 횟수: ${allLogs.length}회');
      print('   - RMS 평균: ${rmsMean.toStringAsFixed(4)}');
      print('   - 주파수 평균: ${freqMean.toStringAsFixed(2)} Hz');
      print('   - 피로도 평균: ${fatigueMean.toStringAsFixed(2)}');
      print('   - User Embedding: $userEmb');

      // SQLite에 저장
      await updateUserState(
        userId: userId,
        userEmb: userEmb,
      );

      print('✅ User Embedding SQLite 저장 완료');
    } catch (e) {
      print('❌ User Embedding 계산 실패: $e');
      print('스택 트레이스: ${StackTrace.current}');
    }
  }

  /// 분산 계산 헬퍼 함수
  double _variance(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;
    final squaredDiffs = values.map((v) => (v - mean) * (v - mean)).toList();
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  /// 데이터베이스 전체 초기화 (개발용)
  Future<void> resetDatabase({String userId = defaultUserId}) async {
    final db = await database;

    // 데이터 삭제
    await db.delete(
      tableFatigueDataset,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await db.delete(
      tableSyncHistory,
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    // user_state 초기화 (baseline은 제거)
    await db.update(
      tableUserState,
      {
        'rms_base': null,
        'freq_base': null,
        'user_emb': jsonEncode(
          [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        ),
        'model_version': '1.0.0',
        'last_sync': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    print('✅ 데이터베이스 초기화 완료');
  }

  /// ========================================
  /// 통계 계산 헬퍼 함수
  /// ========================================

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// ========================================
  /// 동기화 관련 메서드
  /// ========================================

  /// 동기화 완료 처리
  Future<void> markFatigueLogAsSynced(
    String sessionId, {
    String userId = defaultUserId,
  }) async {
    try {
      final db = await database;
      await db.update(
        tableFatigueDataset,
        {'synced': 1},
        where: 'session_id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
      print('✅ 동기화 완료 처리: $sessionId');
    } catch (e) {
      print('❌ 동기화 완료 처리 실패: $e');
    }
  }

  /// ========================================
  /// Baseline 관리
  /// ========================================

  /// Baseline 존재 여부 확인
  Future<bool> hasBaseline() async {
    try {
      final userState = await getUserState();
      if (userState != null) {
        final rmsBase = userState['rms_base'];
        final freqBase = userState['freq_base'];
        return rmsBase != null && freqBase != null;
      }
      return false;
    } catch (e) {
      print('❌ Baseline 존재 여부 확인 실패: $e');
      return false;
    }
  }

  /// Baseline 데이터 저장/업데이트
  Future<bool> saveBaseline(Map<String, dynamic> baselineData) async {
    try {
      final rmsBase = baselineData['fatigueRMS'] ?? 0.0;
      final freqBase = baselineData['peakFreq'] ?? 0.0;

      await updateUserState(
        rmsBase: rmsBase,
        freqBase: freqBase,
      );

      print('✅ Baseline 저장 완료: RMS=$rmsBase, Freq=$freqBase');

      return true;
    } catch (e) {
      print('❌ Baseline 저장 실패: $e');
      return false;
    }
  }

  /// Baseline 초기화
  Future<bool> clearBaseline() async {
    try {
      final db = await database;
      await db.update(
        tableUserState,
        {
          'rms_base': null,
          'freq_base': null,
          'last_sync': DateTime.now().toIso8601String(),
        },
        where: 'user_id = ?',
        whereArgs: [defaultUserId],
      );

      print('✅ Baseline 초기화 완료 (DB null 설정)');
      return true;
    } catch (e) {
      print('❌ Baseline 초기화 실패: $e');
      return false;
    }
  }

  /// 첫 번째 측정인지 확인
  Future<bool> isFirstMeasurement() async {
    try {
      // fatigue_dataset 테이블에 데이터가 있는지 확인
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableFatigueDataset WHERE user_id = ?',
        [defaultUserId],
      );

      final count = result.first['count'] as int;
      return count == 0;
    } catch (e) {
      print('❌ 첫 번째 측정 확인 실패: $e');
      return false;
    }
  }

  /// ========================================
  /// 리소스 정리
  /// ========================================

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
