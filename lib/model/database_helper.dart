import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:math' show sqrt;

/// 통합 데이터베이스 헬퍼 클래스
/// DB_SCHEMA.md (v1.4) 기반으로 전체 DB 관리
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const String dbName = 'fatigue_tracker.db';
  static const int dbVersion = 1;

  // 테이블 이름
  static const String tableBaseline = 'baseline';
  static const String tableUserStats = 'user_stats';
  static const String tableMeasureSessions = 'measure_sessions';
  static const String tableWindowFeatures = 'window_features';

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
    print('🔨 테이블 생성 중...');

    // 1. baseline 테이블
    await db.execute('''
    CREATE TABLE $tableBaseline (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      rms_base REAL NOT NULL,
      freq_base REAL NOT NULL,
      alpha REAL DEFAULT 0.05,
      beta REAL DEFAULT 0.05,
      updated_at TEXT NOT NULL
    )
    ''');
    print('✅ baseline 테이블 생성 완료');

    // 초기 baseline 레코드 삽입
    await db.insert(tableBaseline, {
      'id': 1,
      'rms_base': 0.02, // 일반인 평균
      'freq_base': 1.5, // 일반인 평균 주파수
      'alpha': 0.05,
      'beta': 0.05,
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('✅ baseline 초기 레코드 삽입 완료');

    // 2. user_stats 테이블
    await db.execute('''
    CREATE TABLE $tableUserStats (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      sample_window INTEGER DEFAULT 5,
      meas_count INTEGER DEFAULT 0,
      rms_mean REAL DEFAULT 0.0,
      freq_mean REAL DEFAULT 0.0,
      rms_var REAL DEFAULT 0.0,
      freq_var REAL DEFAULT 0.0,
      fatigue_mean REAL DEFAULT 1.0,
      fatigue_cv REAL DEFAULT 0.0,
      drift_rms REAL DEFAULT 0.0,
      drift_freq REAL DEFAULT 0.0,
      time_of_day_mean REAL DEFAULT 0.0,
      session_len_mean REAL DEFAULT 0.0,
      updated_at TEXT
    )
    ''');
    print('✅ user_stats 테이블 생성 완료');

    // 초기 user_stats 레코드 삽입
    await db.insert(tableUserStats, {
      'id': 1,
      'sample_window': 5,
      'meas_count': 0,
      'rms_mean': 0.0,
      'freq_mean': 0.0,
      'rms_var': 0.0,
      'freq_var': 0.0,
      'fatigue_mean': 1.0,
      'fatigue_cv': 0.0,
      'drift_rms': 0.0,
      'drift_freq': 0.0,
      'time_of_day_mean': 0.0,
      'session_len_mean': 0.0,
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('✅ user_stats 초기 레코드 삽입 완료');

    // 3. measure_sessions 테이블
    await db.execute('''
    CREATE TABLE $tableMeasureSessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      rms REAL,
      freq REAL,
      fatigue REAL,
      mode TEXT,
      window_count INTEGER DEFAULT 0,
      signal_path TEXT,
      synced INTEGER DEFAULT 0
    )
    ''');
    print('✅ measure_sessions 테이블 생성 완료');

    // 4. window_features 테이블
    await db.execute('''
    CREATE TABLE $tableWindowFeatures (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      window_index INTEGER NOT NULL,
      rms REAL NOT NULL,
      freq REAL NOT NULL,
      fatigue_prev REAL,
      fatigue_pred REAL,
      label REAL,
      FOREIGN KEY(session_id) REFERENCES $tableMeasureSessions(id)
    )
    ''');
    print('✅ window_features 테이블 생성 완료');

    print('✅ 모든 테이블 생성 완료');
  }

  /// ========================================
  /// Baseline 관련 메서드
  /// ========================================

  Future<Map<String, dynamic>?> getBaseline() async {
    final db = await database;
    final result = await db.query(
      tableBaseline,
      where: 'id = ?',
      whereArgs: [1],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> updateBaseline({
    required double rmsBase,
    required double freqBase,
    double? alpha,
    double? beta,
  }) async {
    final db = await database;
    await db.update(
      tableBaseline,
      {
        'rms_base': rmsBase,
        'freq_base': freqBase,
        if (alpha != null) 'alpha': alpha,
        if (beta != null) 'beta': beta,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  /// ========================================
  /// User Stats 관련 메서드
  /// ========================================

  Future<Map<String, dynamic>?> getUserStats() async {
    final db = await database;
    final result = await db.query(
      tableUserStats,
      where: 'id = ?',
      whereArgs: [1],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> updateUserStats(Map<String, dynamic> stats) async {
    final db = await database;
    stats['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      tableUserStats,
      stats,
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  /// 최근 N회 측정 기준으로 user_stats 재계산
  Future<void> recalculateUserStats({int n = 5}) async {
    final db = await database;

    // 최근 N회 측정 세션 가져오기
    final sessions = await db.query(
      tableMeasureSessions,
      orderBy: 'timestamp DESC',
      limit: n,
    );

    if (sessions.isEmpty) {
      print('⚠️ 측정 세션이 없어서 user_stats를 재계산할 수 없습니다');
      return;
    }

    // 통계 계산
    final rmsValues = sessions.map((s) => s['rms'] as double? ?? 0.0).toList();
    final freqValues =
        sessions.map((s) => s['freq'] as double? ?? 0.0).toList();
    final fatigueValues =
        sessions.map((s) => s['fatigue'] as double? ?? 1.0).toList();

    final rmsMean = _mean(rmsValues);
    final freqMean = _mean(freqValues);
    final fatigueMean = _mean(fatigueValues);

    final rmsVar = _variance(rmsValues, rmsMean);
    final freqVar = _variance(freqValues, freqMean);
    final fatigueStd = _stdDev(fatigueValues, fatigueMean);
    final fatigueCv = fatigueMean > 0 ? fatigueStd / fatigueMean : 0.0;

    // baseline 가져오기
    final baseline = await getBaseline();
    final rmsBase = baseline?['rms_base'] as double? ?? 0.02;
    final freqBase = baseline?['freq_base'] as double? ?? 1.5;

    final driftRms = rmsMean - rmsBase;
    final driftFreq = freqMean - freqBase;

    // 시간대 평균 (0~1 정규화)
    final timestamps = sessions.map((s) {
      final ts = DateTime.parse(s['timestamp'] as String);
      return ts.hour / 24.0;
    }).toList();
    final timeOfDayMean = _mean(timestamps);

    // 세션 길이 평균 (window_count 기준)
    final windowCounts =
        sessions.map((s) => s['window_count'] as int? ?? 0).toList();
    final sessionLenMean =
        _mean(windowCounts.map((c) => c.toDouble()).toList());

    // DB 업데이트
    await updateUserStats({
      'sample_window': n,
      'meas_count': sessions.length,
      'rms_mean': rmsMean,
      'freq_mean': freqMean,
      'rms_var': rmsVar,
      'freq_var': freqVar,
      'fatigue_mean': fatigueMean,
      'fatigue_cv': fatigueCv,
      'drift_rms': driftRms,
      'drift_freq': driftFreq,
      'time_of_day_mean': timeOfDayMean,
      'session_len_mean': sessionLenMean,
    });

    print('✅ user_stats 재계산 완료 (N=$n, 실제=${sessions.length}회)');
  }

  /// ========================================
  /// Measure Sessions 관련 메서드
  /// ========================================

  Future<int> insertMeasureSession(Map<String, dynamic> session) async {
    final db = await database;
    return await db.insert(tableMeasureSessions, session);
  }

  Future<List<Map<String, dynamic>>> getAllMeasureSessions() async {
    final db = await database;
    return await db.query(
      tableMeasureSessions,
      orderBy: 'timestamp DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getRecentMeasureSessions(int limit) async {
    final db = await database;
    return await db.query(
      tableMeasureSessions,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<int> deleteMeasureSession(int id) async {
    final db = await database;
    return await db.delete(
      tableMeasureSessions,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllMeasureSessions() async {
    final db = await database;
    return await db.delete(tableMeasureSessions);
  }

  /// ========================================
  /// Window Features 관련 메서드
  /// ========================================

  Future<int> insertWindowFeature(Map<String, dynamic> feature) async {
    final db = await database;
    return await db.insert(tableWindowFeatures, feature);
  }

  Future<List<Map<String, dynamic>>> getWindowFeaturesBySession(
    int sessionId,
  ) async {
    final db = await database;
    return await db.query(
      tableWindowFeatures,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'window_index ASC',
    );
  }

  Future<int> deleteWindowFeaturesBySession(int sessionId) async {
    final db = await database;
    return await db.delete(
      tableWindowFeatures,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// ========================================
  /// 통계 및 유틸리티
  /// ========================================

  Future<Map<String, dynamic>> getOverallStats() async {
    final db = await database;

    // 측정 세션 통계
    final sessionStats = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_sessions,
        AVG(fatigue) as avg_fatigue,
        MIN(fatigue) as min_fatigue,
        MAX(fatigue) as max_fatigue,
        AVG(rms) as avg_rms,
        AVG(freq) as avg_freq
      FROM $tableMeasureSessions
    ''');

    // 오늘 측정 수
    final today = DateTime.now();
    final todayStart =
        DateTime(today.year, today.month, today.day).toIso8601String();
    final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59)
        .toIso8601String();

    final todayCount = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM $tableMeasureSessions
      WHERE timestamp >= ? AND timestamp <= ?
    ''',
      [todayStart, todayEnd],
    );

    return {
      'total_sessions': sessionStats.first['total_sessions'] ?? 0,
      'avg_fatigue': sessionStats.first['avg_fatigue'] ?? 1.0,
      'min_fatigue': sessionStats.first['min_fatigue'] ?? 1.0,
      'max_fatigue': sessionStats.first['max_fatigue'] ?? 1.0,
      'avg_rms': sessionStats.first['avg_rms'] ?? 0.0,
      'avg_freq': sessionStats.first['avg_freq'] ?? 0.0,
      'today_sessions': todayCount.first['count'] ?? 0,
    };
  }

  /// 데이터베이스 전체 초기화 (개발용)
  Future<void> resetDatabase() async {
    final db = await database;
    await db.delete(tableMeasureSessions);
    await db.delete(tableWindowFeatures);
    await db.delete(tableUserStats);
    await db.delete(tableBaseline);

    // 기본값 재삽입
    await db.insert(tableBaseline, {
      'id': 1,
      'rms_base': 0.02,
      'freq_base': 1.5,
      'alpha': 0.05,
      'beta': 0.05,
      'updated_at': DateTime.now().toIso8601String(),
    });

    await db.insert(tableUserStats, {
      'id': 1,
      'sample_window': 5,
      'meas_count': 0,
      'rms_mean': 0.0,
      'freq_mean': 0.0,
      'rms_var': 0.0,
      'freq_var': 0.0,
      'fatigue_mean': 1.0,
      'fatigue_cv': 0.0,
      'drift_rms': 0.0,
      'drift_freq': 0.0,
      'time_of_day_mean': 0.0,
      'session_len_mean': 0.0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    print('✅ 데이터베이스 초기화 완료');
  }

  /// ========================================
  /// 통계 계산 헬퍼 함수
  /// ========================================

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _variance(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;
    final squaredDiffs = values.map((v) => (v - mean) * (v - mean));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  double _stdDev(List<double> values, double mean) {
    return sqrt(_variance(values, mean));
  }

  /// ========================================
  /// 리소스 정리
  /// ========================================

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
