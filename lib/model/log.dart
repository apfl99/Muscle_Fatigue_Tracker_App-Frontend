import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'config.dart';

/// 근피로도 측정 결과 모델
class FatigueResult {
  final int? id;
  final DateTime timestamp;
  final double rms;
  final double variance;
  final double peakFreq;
  final double meanPowerFreq;
  final double medianFreq;
  final double fatigue;
  final int sampleCount;
  final double samplingRate;

  FatigueResult({
    this.id,
    required this.timestamp,
    required this.rms,
    required this.variance,
    required this.peakFreq,
    required this.meanPowerFreq,
    required this.medianFreq,
    required this.fatigue,
    required this.sampleCount,
    required this.samplingRate,
  });

  // Map으로 변환 (DB 저장용)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'rms': rms,
      'variance': variance,
      'peak_freq': peakFreq,
      'mean_power_freq': meanPowerFreq,
      'median_freq': medianFreq,
      'fatigue': fatigue,
      'sample_count': sampleCount,
      'sampling_rate': samplingRate,
    };
  }

  // Map에서 생성
  factory FatigueResult.fromMap(Map<String, dynamic> map) {
    return FatigueResult(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      rms: map['rms'] as double,
      variance: map['variance'] as double,
      peakFreq: map['peak_freq'] as double,
      meanPowerFreq: map['mean_power_freq'] as double,
      medianFreq: map['median_freq'] as double,
      fatigue: map['fatigue'] as double,
      sampleCount: map['sample_count'] as int,
      samplingRate: map['sampling_rate'] as double,
    );
  }

  @override
  String toString() {
    return 'FatigueResult{id: $id, timestamp: $timestamp, rms: $rms, '
        'variance: $variance, peakFreq: $peakFreq, fatigue: $fatigue}';
  }
}

/// SQLite 데이터베이스 관리 클래스
class FatigueDatabase {
  static final FatigueDatabase instance = FatigueDatabase._init();
  static Database? _database;

  FatigueDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(DatabaseConstants.fatigueDbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      print('📱 플랫폼: ${Platform.operatingSystem}');

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      print('📂 데이터베이스 경로: $path');

      // 파일 존재 확인
      final file = File(path);
      final exists = await file.exists();
      print('📄 DB 파일 존재: ${exists ? "예" : "아니오"}');

      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          print('🆕 새 데이터베이스 생성 (onCreate 호출)');
          await _createDB(db, version);
        },
        onOpen: (db) async {
          print('✅ 데이터베이스 열림');
          // 테이블 존재 확인
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseConstants.fatigueTableName}'",
          );
          print('📊 테이블 확인: ${tables.isNotEmpty ? "존재함" : "없음"}');

          if (tables.isNotEmpty) {
            // 레코드 수 확인
            final count = await db.rawQuery(
              'SELECT COUNT(*) as count FROM ${DatabaseConstants.fatigueTableName}',
            );
            print('📊 현재 레코드 수: ${count[0]['count']}개');
          }
        },
      );

      print('✅ 데이터베이스 초기화 완료');
      return db;
    } catch (e, stackTrace) {
      print('❌ 데이터베이스 초기화 오류: $e');
      print('스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  Future _createDB(Database db, int version) async {
    print('🔨 데이터베이스 테이블 생성 중...');

    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';

    try {
      await db.execute('''
    CREATE TABLE ${DatabaseConstants.fatigueTableName} (
      id $idType,
      timestamp $integerType,
      rms $realType,
      variance $realType,
      peak_freq $realType,
      mean_power_freq $realType,
      median_freq $realType,
      fatigue $realType,
      sample_count $integerType,
      sampling_rate $realType
    )
    ''');

      print('✅ 데이터베이스 테이블 생성 완료');

      // 테이블 구조 확인
      final columns = await db
          .rawQuery('PRAGMA table_info(${DatabaseConstants.fatigueTableName})');
      print('📋 테이블 컬럼: ${columns.length}개');
      for (var col in columns) {
        print('   - ${col['name']}: ${col['type']}');
      }
    } catch (e) {
      print('❌ 테이블 생성 오류: $e');
      rethrow;
    }
  }

  /// 측정 결과 저장
  Future<int> insertResult(FatigueResult result) async {
    try {
      print('\n💾 데이터베이스 저장 시작...');
      final db = await instance.database;

      final dataMap = result.toMap();
      print('📝 저장할 데이터: $dataMap');

      final id = await db.insert(
        DatabaseConstants.fatigueTableName,
        dataMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ 측정 결과 저장 완료 (ID: $id)');
      print('   - RMS: ${result.rms.toStringAsFixed(4)}');
      print('   - Variance: ${result.variance.toStringAsFixed(4)}');
      print('   - Peak Freq: ${result.peakFreq.toStringAsFixed(2)} Hz');
      print('   - Fatigue: ${result.fatigue.toStringAsFixed(2)}');

      // 저장 확인
      final savedData = await db.query(
        DatabaseConstants.fatigueTableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      print('🔍 저장 확인: ${savedData.isNotEmpty ? "성공" : "실패"}');

      return id;
    } catch (e) {
      print('❌ 데이터 저장 오류: $e');
      rethrow;
    }
  }

  /// 모든 결과 조회 (최신순)
  Future<List<FatigueResult>> getAllResults() async {
    final db = await instance.database;
    final result = await db.query(
      DatabaseConstants.fatigueTableName,
      orderBy: 'timestamp DESC',
    );

    return result.map((map) => FatigueResult.fromMap(map)).toList();
  }

  /// 특정 기간의 결과 조회
  Future<List<FatigueResult>> getResultsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      DatabaseConstants.fatigueTableName,
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
    );

    return result.map((map) => FatigueResult.fromMap(map)).toList();
  }

  /// 최근 N개 결과 조회
  Future<List<FatigueResult>> getRecentResults(int limit) async {
    try {
      final db = await instance.database;
      print('📂 데이터베이스 쿼리 실행 (최근 $limit개)');

      final result = await db.query(
        DatabaseConstants.fatigueTableName,
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      print('✅ 쿼리 결과: ${result.length}개');

      final results = result.map((map) => FatigueResult.fromMap(map)).toList();

      if (results.isNotEmpty) {
        print('📊 최근 결과:');
        for (int i = 0; i < min(3, results.length); i++) {
          final r = results[i];
          print(
            '   ${i + 1}. 피로도: ${r.fatigue.toStringAsFixed(2)}, RMS: ${r.rms.toStringAsFixed(4)}',
          );
        }
      }

      return results;
    } catch (e) {
      print('❌ getRecentResults 오류: $e');
      return [];
    }
  }

  /// 특정 ID 결과 조회
  Future<FatigueResult?> getResult(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      DatabaseConstants.fatigueTableName,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return FatigueResult.fromMap(maps.first);
    }
    return null;
  }

  /// 결과 삭제
  Future<int> deleteResult(int id) async {
    final db = await instance.database;
    return await db.delete(
      DatabaseConstants.fatigueTableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 모든 결과 삭제
  Future<int> deleteAllResults() async {
    final db = await instance.database;
    return await db.delete(DatabaseConstants.fatigueTableName);
  }

  /// 통계 조회
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        AVG(rms) as avg_rms,
        AVG(variance) as avg_variance,
        AVG(peak_freq) as avg_freq,
        AVG(fatigue) as avg_fatigue,
        MIN(fatigue) as min_fatigue,
        MAX(fatigue) as max_fatigue
      FROM ${DatabaseConstants.fatigueTableName}
    ''');

    if (result.isNotEmpty) {
      return result.first;
    }
    return {};
  }

  /// 데이터베이스 닫기
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}

/// 근피로도 계산 헬퍼 클래스
class FatigueCalculator {
  /// 근피로도 점수 계산
  /// Fatigue = α·(RMS/RMS_base) + β·(Freq_base/Freq)
  /// - RMS가 높을수록 피로도 증가
  /// - 주파수가 낮을수록 피로도 증가
  static double calculateFatigue({
    required double rms,
    required double peakFreq,
    required double rmsBase,
    required double freqBase,
  }) {
    // 0으로 나누기 방지 및 무효값 처리
    if (rmsBase <= 0 || peakFreq <= 0 || rms.isNaN || peakFreq.isNaN) {
      print('⚠️ 피로도 계산 불가: rmsBase=$rmsBase, peakFreq=$peakFreq');
      return FatigueConstants.minFatigue; // 1.0 반환
    }

    final fatigue = FatigueConstants.alpha * (rms / rmsBase) +
        FatigueConstants.beta * (freqBase / peakFreq);

    // NaN 체크
    if (fatigue.isNaN || fatigue.isInfinite) {
      print('⚠️ 피로도 계산 결과 무효: $fatigue');
      return FatigueConstants.minFatigue;
    }

    // 최소 1.0으로 클램프
    final clampedFatigue = fatigue.clamp(
      FatigueConstants.minFatigue,
      FatigueConstants.maxFatigue,
    );

    // 소수점 3자리로 반올림
    final roundedFatigue = double.parse(clampedFatigue.toStringAsFixed(3));

    print('🧮 피로도 계산:');
    print(
      '   - 공식: ${FatigueConstants.alpha} × ($rms / $rmsBase) + ${FatigueConstants.beta} × ($freqBase / $peakFreq)',
    );
    print('   - 원본 결과: ${fatigue.toStringAsFixed(3)}');
    print('   - 최종 결과: ${roundedFatigue.toStringAsFixed(3)}');

    return roundedFatigue;
  }

  /// 피로도 레벨 텍스트 반환 (새 기준)
  static String getFatigueLevel(double fatigue) {
    if (fatigue < FatigueConstants.normalThreshold) return '정상';
    if (fatigue < FatigueConstants.lightThreshold) return '약간 피로';
    if (fatigue < FatigueConstants.midThreshold) return '피로 누적';
    return '고피로';
  }

  /// 피로도 레벨 색상 반환 (새 기준)
  static Color getFatigueColor(double fatigue) {
    if (fatigue < FatigueConstants.normalThreshold) return Colors.green;
    if (fatigue < FatigueConstants.lightThreshold) return Colors.yellow;
    if (fatigue < FatigueConstants.midThreshold) return Colors.orange;
    return Colors.red;
  }

  /// 게이지 값 변환 (0-100%)
  static double fatigueToGauge(double fatigue) {
    return GaugeConstants.fatigueToGauge(fatigue);
  }

  /// 변화량 분석 (트렌드)
  static String getFatigueTrend(double prev, double current) {
    final delta = current - prev;

    if (delta.abs() < FatigueConstants.noChangeDelta) return '변화 없음';
    if (delta > FatigueConstants.heavyIncreaseDelta) return '피로도 급상승';
    if (delta > FatigueConstants.lightIncreaseDelta) return '피로 상승';
    if (delta < -FatigueConstants.lightIncreaseDelta) return '회복 중';
    return '유지';
  }

  /// 트렌드 아이콘
  static IconData getFatigueTrendIcon(double prev, double current) {
    final delta = current - prev;

    if (delta.abs() < FatigueConstants.noChangeDelta)
      return Icons.horizontal_rule;
    if (delta > FatigueConstants.heavyIncreaseDelta) return Icons.trending_up;
    if (delta > FatigueConstants.lightIncreaseDelta) return Icons.arrow_upward;
    if (delta < -FatigueConstants.lightIncreaseDelta)
      return Icons.arrow_downward;
    return Icons.horizontal_rule;
  }
}
