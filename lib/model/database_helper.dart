import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert';
import 'user_stats.dart';

/// 통합 데이터베이스 헬퍼 클래스
/// DB_SCHEMA.md (v1.0.0) 기반으로 전체 DB 관리
/// Oracle Autonomous Database 스키마를 SQLite로 변환
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const String dbName = 'fatigue_tracker.db';
  static const int dbVersion = 2;

  // 테이블 이름 (DB_SCHEMA.md 기준)
  static const String tableUsers = 'users';
  static const String tableUserState = 'user_state';
  static const String tableFatigueLogs = 'fatigue_logs';
  static const String tableModelVersions = 'model_versions';
  static const String tableSyncHistory = 'sync_history';

  // 임시 측정 데이터 (5회마다 DB 저장)
  static const String tableTempMeasurements = 'temp_measurements';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    try {
      print('🗄️ 데이터베이스 초기화 시작...');
      print('📱 플랫폼: ${Platform.operatingSystem}');

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, dbName);

      print('📂 DB 경로: $path');

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
    print('🔨 테이블 생성 중 (DB_SCHEMA.md v1.0.0 기준)...');

    // 1. users 테이블 (로컬 앱용 단순화)
    await db.execute('''
    CREATE TABLE $tableUsers (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT,
      created_at TEXT NOT NULL
    )
    ''');
    print('✅ users 테이블 생성 완료');

    // 로컬 사용자 기본 레코드 삽입
    await db.insert(tableUsers, {
      'id': 'local_user',
      'email': 'local@device',
      'password_hash': '',
      'created_at': DateTime.now().toIso8601String(),
    });
    print('✅ users 초기 레코드 삽입 완료');

    // 2. user_state 테이블
    await db.execute('''
    CREATE TABLE $tableUserState (
      user_id TEXT PRIMARY KEY,
      rms_base REAL,
      freq_base REAL,
      user_emb TEXT,
      model_version TEXT,
      last_sync TEXT,
      FOREIGN KEY(user_id) REFERENCES $tableUsers(id)
    )
    ''');
    print('✅ user_state 테이블 생성 완료');

    // 초기 user_state 레코드 삽입
    await db.insert(tableUserState, {
      'user_id': 'local_user',
      'rms_base': 0.02,
      'freq_base': 1.5,
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
    });
    print('✅ user_state 초기 레코드 삽입 완료');

    // 3. fatigue_logs 테이블
    await db.execute('''
    CREATE TABLE $tableFatigueLogs (
      user_id TEXT NOT NULL,
      session_id TEXT PRIMARY KEY,
      measure_date TEXT NOT NULL,
      rms REAL,
      freq REAL,
      fatigue REAL,
      mode TEXT,
      window_count INTEGER,
      created_at TEXT NOT NULL,
      synced INTEGER DEFAULT 0,
      FOREIGN KEY(user_id) REFERENCES $tableUsers(id)
    )
    ''');
    print('✅ fatigue_logs 테이블 생성 완료');

    // 인덱스 생성
    await db
        .execute('CREATE INDEX idx_logs_user ON $tableFatigueLogs(user_id)');
    await db.execute(
      'CREATE INDEX idx_logs_date ON $tableFatigueLogs(measure_date)',
    );
    print('✅ fatigue_logs 인덱스 생성 완료');

    // 4. model_versions 테이블
    await db.execute('''
    CREATE TABLE $tableModelVersions (
      model_type TEXT PRIMARY KEY,
      version TEXT,
      path TEXT,
      updated_at TEXT NOT NULL
    )
    ''');
    print('✅ model_versions 테이블 생성 완료');

    // 초기 모델 버전 레코드
    await db.insert(tableModelVersions, {
      'model_type': 'EMA',
      'version': '1.0.0',
      'path': 'local',
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert(tableModelVersions, {
      'model_type': 'Hybrid',
      'version': '1.0.0',
      'path': 'local',
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert(tableModelVersions, {
      'model_type': 'E2E',
      'version': '1.0.0',
      'path': 'local',
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('✅ model_versions 초기 레코드 삽입 완료');

    // 5. sync_history 테이블
    await db.execute('''
    CREATE TABLE $tableSyncHistory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      sync_type TEXT NOT NULL,
      status TEXT NOT NULL,
      executed_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES $tableUsers(id)
    )
    ''');
    print('✅ sync_history 테이블 생성 완료');

    // 6. temp_measurements 테이블 (5회 측정마다 DB 저장용)
    await db.execute('''
    CREATE TABLE $tableTempMeasurements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      window_index INTEGER NOT NULL,
      rms REAL NOT NULL,
      freq REAL NOT NULL,
      fatigue REAL,
      timestamp TEXT NOT NULL
    )
    ''');
    print('✅ temp_measurements 테이블 생성 완료');

    print('✅ 모든 테이블 생성 완료 (DB_SCHEMA.md v1.0.0)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 데이터베이스 업그레이드 중... ($oldVersion → $newVersion)');

    if (oldVersion < 2) {
      // 기존 데이터 마이그레이션
      try {
        // 기존 테이블 확인
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        print('📋 기존 테이블: ${tables.map((t) => t['name']).toList()}');

        // 새 테이블 생성
        await _createDB(db, newVersion);

        print('✅ 업그레이드 완료');
      } catch (e) {
        print('⚠️ 업그레이드 중 오류: $e');
        // 기존 테이블이 있다면 삭제하고 재생성
        await db.execute('DROP TABLE IF EXISTS baseline');
        await db.execute('DROP TABLE IF EXISTS user_stats');
        await db.execute('DROP TABLE IF EXISTS measure_sessions');
        await db.execute('DROP TABLE IF EXISTS window_features');
        await _createDB(db, newVersion);
      }
    }
  }

  /// ========================================
  /// User State 관련 메서드 (baseline + user_emb)
  /// ========================================

  Future<Map<String, dynamic>?> getUserState({
    String userId = 'local_user',
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
    String userId = 'local_user',
    double? rmsBase,
    double? freqBase,
    List<double>? userEmb,
    String? modelVersion,
  }) async {
    final db = await database;
    final updateData = <String, dynamic>{
      'last_sync': DateTime.now().toIso8601String(),
    };

    if (rmsBase != null) updateData['rms_base'] = rmsBase;
    if (freqBase != null) updateData['freq_base'] = freqBase;
    if (userEmb != null) updateData['user_emb'] = jsonEncode(userEmb);
    if (modelVersion != null) updateData['model_version'] = modelVersion;

    await db.update(
      tableUserState,
      updateData,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<double>> getUserEmbedding({String userId = 'local_user'}) async {
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

  Future<int> insertFatigueLog({
    String userId = 'local_user',
    required String sessionId,
    required DateTime measureDate,
    required double rms,
    required double freq,
    required double fatigue,
    required String mode,
    required int windowCount,
  }) async {
    final db = await database;

    final logData = {
      'user_id': userId,
      'session_id': sessionId,
      'measure_date': measureDate.toIso8601String().split('T')[0], // DATE only
      'rms': rms,
      'freq': freq,
      'fatigue': fatigue,
      'mode': mode,
      'window_count': windowCount,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    };

    try {
      await db.insert(tableFatigueLogs, logData);
      print('✅ 피로도 로그 저장: $sessionId (피로도: $fatigue)');
      return 1;
    } catch (e) {
      print('❌ 피로도 로그 저장 실패: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getAllFatigueLogs({
    String userId = 'local_user',
  }) async {
    final db = await database;
    return await db.query(
      tableFatigueLogs,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getRecentFatigueLogs({
    String userId = 'local_user',
    int limit = 10,
  }) async {
    final db = await database;
    return await db.query(
      tableFatigueLogs,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getFatigueLogsByDateRange({
    String userId = 'local_user',
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await database;
    return await db.query(
      tableFatigueLogs,
      where: 'user_id = ? AND measure_date >= ? AND measure_date <= ?',
      whereArgs: [
        userId,
        startDate.toIso8601String().split('T')[0],
        endDate.toIso8601String().split('T')[0],
      ],
      orderBy: 'measure_date DESC',
    );
  }

  Future<int> deleteFatigueLog(String sessionId) async {
    final db = await database;
    return await db.delete(
      tableFatigueLogs,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> deleteAllFatigueLogs({String userId = 'local_user'}) async {
    final db = await database;
    return await db.delete(
      tableFatigueLogs,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLogs({
    String userId = 'local_user',
  }) async {
    final db = await database;
    return await db.query(
      tableFatigueLogs,
      where: 'user_id = ? AND synced = 0',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markLogsAsSynced(List<String> sessionIds) async {
    final db = await database;
    for (final sessionId in sessionIds) {
      await db.update(
        tableFatigueLogs,
        {'synced': 1},
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    }
    print('✅ ${sessionIds.length}개 로그 동기화 완료 표시');
  }

  /// ========================================
  /// Temp Measurements 관련 메서드 (5회마다 DB 저장)
  /// ========================================

  Future<int> insertTempMeasurement({
    required String sessionId,
    required int windowIndex,
    required double rms,
    required double freq,
    double? fatigue,
  }) async {
    final db = await database;

    final data = {
      'session_id': sessionId,
      'window_index': windowIndex,
      'rms': rms,
      'freq': freq,
      'fatigue': fatigue,
      'timestamp': DateTime.now().toIso8601String(),
    };

    return await db.insert(tableTempMeasurements, data);
  }

  Future<List<Map<String, dynamic>>> getTempMeasurementsBySession(
    String sessionId,
  ) async {
    final db = await database;
    return await db.query(
      tableTempMeasurements,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'window_index ASC',
    );
  }

  Future<int> getTempMeasurementCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableTempMeasurements',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearTempMeasurements() async {
    final db = await database;
    await db.delete(tableTempMeasurements);
    print('✅ 임시 측정 데이터 삭제 완료');
  }

  /// 5회 측정마다 DB에 저장하는 로직
  Future<bool> shouldSaveToDatabase() async {
    final count = await getTempMeasurementCount();
    return count >= 5;
  }

  /// 임시 측정 데이터를 fatigue_logs로 이동
  Future<void> commitTempMeasurementsToLogs({
    String userId = 'local_user',
    required String sessionId,
    required double avgRms,
    required double avgFreq,
    required double avgFatigue,
    required String mode,
    required int windowCount,
  }) async {
    // fatigue_logs에 저장
    await insertFatigueLog(
      userId: userId,
      sessionId: sessionId,
      measureDate: DateTime.now(),
      rms: avgRms,
      freq: avgFreq,
      fatigue: avgFatigue,
      mode: mode,
      windowCount: windowCount,
    );

    // 임시 데이터 삭제
    await clearTempMeasurements();

    print('✅ 임시 측정 데이터를 DB에 커밋 완료');
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
    String userId = 'local_user',
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
    String userId = 'local_user',
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
    String userId = 'local_user',
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
    String userId = 'local_user',
  }) async {
    final db = await database;

    // 피로도 로그 통계
    final logStats = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as total_logs,
        AVG(fatigue) as avg_fatigue,
        MIN(fatigue) as min_fatigue,
        MAX(fatigue) as max_fatigue,
        AVG(rms) as avg_rms,
        AVG(freq) as avg_freq
      FROM $tableFatigueLogs
      WHERE user_id = ?
    ''',
      [userId],
    );

    // 오늘 측정 수
    final today = DateTime.now();
    final todayDate = today.toIso8601String().split('T')[0];

    final todayCount = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM $tableFatigueLogs
      WHERE user_id = ? AND measure_date = ?
    ''',
      [userId, todayDate],
    );

    // 최근 7일 평균
    final weekAgo = today.subtract(const Duration(days: 7));
    final weekAgoDate = weekAgo.toIso8601String().split('T')[0];

    final weekStats = await db.rawQuery(
      '''
      SELECT AVG(fatigue) as week_avg_fatigue
      FROM $tableFatigueLogs
      WHERE user_id = ? AND measure_date >= ?
    ''',
      [userId, weekAgoDate],
    );

    return {
      'total_logs': logStats.first['total_logs'] ?? 0,
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
    String userId = 'local_user',
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
    String userId = 'local_user',
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
  Future<void> resetDatabase({String userId = 'local_user'}) async {
    final db = await database;

    // 데이터 삭제
    await db
        .delete(tableFatigueLogs, where: 'user_id = ?', whereArgs: [userId]);
    await db.delete(tableTempMeasurements);
    await db
        .delete(tableSyncHistory, where: 'user_id = ?', whereArgs: [userId]);

    // user_state 초기화
    await db.update(
      tableUserState,
      {
        'rms_base': 0.02,
        'freq_base': 1.5,
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
  Future<void> markFatigueLogAsSynced(String sessionId) async {
    try {
      final db = await database;
      await db.update(
        tableFatigueLogs,
        {'synced': 1},
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      print('✅ 동기화 완료 처리: $sessionId');
    } catch (e) {
      print('❌ 동기화 완료 처리 실패: $e');
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
