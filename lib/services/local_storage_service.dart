import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/fatigue_result.dart';
import '../models/user_baseline.dart';

/// 로컬 저장소 서비스 (SQLite + SharedPreferences)
class LocalStorageService {
  static Database? _database;
  static SharedPreferences? _prefs;

  /// 데이터베이스 초기화
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fatigue_tracker.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 측정 결과 테이블
        await db.execute('''
          CREATE TABLE fatigue_results (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            fatigueIndex REAL NOT NULL,
            rms REAL NOT NULL,
            variance REAL NOT NULL,
            dominantFrequency REAL NOT NULL,
            userId TEXT
          )
        ''');

        // 인덱스 생성
        await db.execute('''
          CREATE INDEX idx_timestamp ON fatigue_results(timestamp DESC)
        ''');
      },
    );
  }

  /// SharedPreferences 초기화
  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 측정 결과 저장
  Future<void> saveFatigueResult(FatigueResult result) async {
    final db = await database;
    await db.insert(
      'fatigue_results',
      result.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 최근 측정 결과 조회
  Future<List<FatigueResult>> getRecentResults({int limit = 30}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'fatigue_results',
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) => FatigueResult.fromJson(maps[i]));
  }

  /// 기간별 측정 결과 조회
  Future<List<FatigueResult>> getResultsByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'fatigue_results',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) => FatigueResult.fromJson(maps[i]));
  }

  /// Baseline 저장
  Future<void> saveBaseline(UserBaseline baseline) async {
    final prefs = await this.prefs;
    await prefs.setString('user_baseline', jsonEncode(baseline.toJson()));
  }

  /// Baseline 불러오기
  Future<UserBaseline?> loadBaseline() async {
    final prefs = await this.prefs;
    final baselineJson = prefs.getString('user_baseline');
    if (baselineJson == null) return null;

    return UserBaseline.fromJson(jsonDecode(baselineJson));
  }

  /// 현재 사용자 ID 저장
  Future<void> saveUserId(String userId) async {
    final prefs = await this.prefs;
    await prefs.setString('current_user_id', userId);
  }

  /// 현재 사용자 ID 불러오기
  Future<String?> loadUserId() async {
    final prefs = await this.prefs;
    return prefs.getString('current_user_id');
  }

  /// 로그아웃 (로컬 데이터 유지, 사용자 정보만 제거)
  Future<void> clearUserData() async {
    final prefs = await this.prefs;
    await prefs.remove('current_user_id');
  }
}

