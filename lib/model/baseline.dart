import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:math';
import 'config.dart';

/// Baseline 데이터 모델
class BaselineData {
  final int? id;
  final DateTime timestamp;
  final double rmsBase;
  final double freqBase;
  final int sampleCount; // baseline 계산에 사용된 측정 횟수

  BaselineData({
    this.id,
    required this.timestamp,
    required this.rmsBase,
    required this.freqBase,
    required this.sampleCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'rms_base': rmsBase,
      'freq_base': freqBase,
      'sample_count': sampleCount,
    };
  }

  factory BaselineData.fromMap(Map<String, dynamic> map) {
    return BaselineData(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      rmsBase: map['rms_base'] as double,
      freqBase: map['freq_base'] as double,
      sampleCount: map['sample_count'] as int,
    );
  }
}

/// Baseline 자동 보정 관리 클래스
class BaselineManager {
  static final BaselineManager instance = BaselineManager._init();
  static Database? _database;

  // 현재 baseline 값 (메모리에 캐시)
  double _currentRmsBase = BaselineConstants.defaultRmsBase;
  double _currentFreqBase = BaselineConstants.defaultFreqBase;

  BaselineManager._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(DatabaseConstants.baselineDbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      print('📊 Baseline 데이터베이스 초기화...');
      print('📱 플랫폼: ${Platform.operatingSystem}');

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      print('📂 Baseline DB 경로: $path');

      final db = await openDatabase(
        path,
        version: 1,
        onCreate: _createDB,
        onOpen: (db) async {
          print('✅ Baseline DB 열림');
        },
      );

      print('✅ Baseline 데이터베이스 초기화 완료');

      // 최신 baseline 로드 (db를 직접 전달하여 무한 루프 방지)
      await _loadLatestBaselineFromDB(db);

      return db;
    } catch (e, stackTrace) {
      print('❌ Baseline DB 초기화 오류: $e');
      print('스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  Future _createDB(Database db, int version) async {
    print('🔨 Baseline 테이블 생성 중...');

    await db.execute('''
    CREATE TABLE ${DatabaseConstants.baselineTableName} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp INTEGER NOT NULL,
      rms_base REAL NOT NULL,
      freq_base REAL NOT NULL,
      sample_count INTEGER NOT NULL
    )
    ''');

    print('✅ Baseline 테이블 생성 완료');
  }

  /// 최신 baseline 로드 (DB 인스턴스 직접 전달)
  Future<void> _loadLatestBaselineFromDB(Database db) async {
    try {
      print('📂 Baseline 로드 중...');
      final result = await db.query(
        DatabaseConstants.baselineTableName,
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      if (result.isNotEmpty) {
        final baseline = BaselineData.fromMap(result.first);
        _currentRmsBase = baseline.rmsBase;
        _currentFreqBase = baseline.freqBase;

        print('✅ Baseline 로드 완료:');
        print('   - RMS Base: ${_currentRmsBase.toStringAsFixed(4)}');
        print('   - Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz');
        print('   - 샘플 수: ${baseline.sampleCount}개');
      } else {
        print('ℹ️ 저장된 Baseline 없음, 기본값 사용');
        print('   - RMS Base: ${_currentRmsBase.toStringAsFixed(4)}');
        print('   - Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz');
      }
    } catch (e) {
      print('❌ Baseline 로드 오류: $e');
    }
  }

  /// 현재 baseline 값 반환
  double get rmsBase => _currentRmsBase;
  double get freqBase => _currentFreqBase;

  /// 새로운 측정값으로 baseline 업데이트 (Moving Average)
  Future<void> updateBaseline(double newRms, double newFreq) async {
    try {
      print('\n📈 Baseline 업데이트 시도...');
      print('   - 새 RMS: ${newRms.toStringAsFixed(4)}');
      print('   - 새 Freq: ${newFreq.toStringAsFixed(2)} Hz');

      final db = await database;

      // 최근 N개 데이터 가져오기
      final recentData = await db.query(
        DatabaseConstants.baselineTableName,
        orderBy: 'timestamp DESC',
        limit: BaselineConstants.movingAverageWindow,
      );

      List<double> rmsList = [];
      List<double> freqList = [];

      // 기존 데이터 수집
      for (var data in recentData) {
        rmsList.add(data['rms_base'] as double);
        freqList.add(data['freq_base'] as double);
      }

      // Outlier 검출 (급격한 변화 제외)
      bool isRmsOutlier = false;
      bool isFreqOutlier = false;

      if (rmsList.length >= 2) {
        final rmsMean = rmsList.reduce((a, b) => a + b) / rmsList.length;
        final rmsStdDev = _calculateStdDev(rmsList, rmsMean);

        print(
          '📊 RMS 통계: 평균=${rmsMean.toStringAsFixed(4)}, StdDev=${rmsStdDev.toStringAsFixed(4)}',
        );

        if (rmsStdDev != double.infinity &&
            (newRms - rmsMean).abs() >
                rmsStdDev * BaselineConstants.outlierThreshold) {
          isRmsOutlier = true;
          print(
            '⚠️ RMS Outlier 감지: ${newRms.toStringAsFixed(4)} (평균: ${rmsMean.toStringAsFixed(4)}, 허용범위: ±${(rmsStdDev * BaselineConstants.outlierThreshold).toStringAsFixed(4)})',
          );
        } else {
          print('✓ RMS 정상 범위');
        }
      } else {
        print('ℹ️ RMS 데이터 부족 (${rmsList.length}개) - Outlier 검사 건너뜀');
      }

      if (freqList.length >= 2) {
        final freqMean = freqList.reduce((a, b) => a + b) / freqList.length;
        final freqStdDev = _calculateStdDev(freqList, freqMean);

        print(
          '📊 Freq 통계: 평균=${freqMean.toStringAsFixed(2)}, StdDev=${freqStdDev.toStringAsFixed(2)}',
        );

        if (freqStdDev != double.infinity &&
            (newFreq - freqMean).abs() >
                freqStdDev * BaselineConstants.outlierThreshold) {
          isFreqOutlier = true;
          print(
            '⚠️ Freq Outlier 감지: ${newFreq.toStringAsFixed(2)} Hz (평균: ${freqMean.toStringAsFixed(2)}, 허용범위: ±${(freqStdDev * BaselineConstants.outlierThreshold).toStringAsFixed(2)})',
          );
        } else {
          print('✓ Freq 정상 범위');
        }
      } else {
        print('ℹ️ Freq 데이터 부족 (${freqList.length}개) - Outlier 검사 건너뜀');
      }

      // Outlier가 아닌 경우에만 업데이트
      if (!isRmsOutlier && !isFreqOutlier) {
        print('✅ Outlier 검사 통과 - 업데이트 진행');

        // 새 데이터 추가
        rmsList.insert(0, newRms);
        freqList.insert(0, newFreq);

        // Moving Average 계산 (최근 N개)
        if (rmsList.length > BaselineConstants.movingAverageWindow) {
          rmsList = rmsList.sublist(0, BaselineConstants.movingAverageWindow);
        }
        if (freqList.length > BaselineConstants.movingAverageWindow) {
          freqList = freqList.sublist(0, BaselineConstants.movingAverageWindow);
        }

        final oldRmsBase = _currentRmsBase;
        final oldFreqBase = _currentFreqBase;

        _currentRmsBase = rmsList.reduce((a, b) => a + b) / rmsList.length;
        _currentFreqBase = freqList.reduce((a, b) => a + b) / freqList.length;

        // DB에 저장
        final baseline = BaselineData(
          timestamp: DateTime.now(),
          rmsBase: _currentRmsBase,
          freqBase: _currentFreqBase,
          sampleCount: rmsList.length,
        );

        final id = await db.insert('baseline', baseline.toMap());

        print('✅ Baseline 업데이트 완료 (ID: $id):');
        print(
          '   - 이전 RMS Base: ${oldRmsBase.toStringAsFixed(4)} → 새 RMS Base: ${_currentRmsBase.toStringAsFixed(4)}',
        );
        print(
          '   - 이전 Freq Base: ${oldFreqBase.toStringAsFixed(2)} Hz → 새 Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz',
        );
        print('   - 평균 계산 샘플: ${rmsList.length}개');

        // 저장 확인
        final count = await db.rawQuery(
          'SELECT COUNT(*) as count FROM ${DatabaseConstants.baselineTableName}',
        );
        print('   - 총 Baseline 레코드: ${count[0]['count']}개');
      } else {
        print('❌ Outlier로 인해 Baseline 업데이트 제외');
        if (isRmsOutlier) print('   - RMS가 outlier');
        if (isFreqOutlier) print('   - Freq가 outlier');
      }
    } catch (e) {
      print('❌ Baseline 업데이트 오류: $e');
    }
  }

  /// 표준편차 계산
  double _calculateStdDev(List<double> data, double mean) {
    if (data.length < 2)
      return double.infinity; // 데이터 부족 시 큰 값 반환 (outlier 방지 안 함)

    double sumSquaredDiff = 0.0;
    for (final value in data) {
      final diff = value - mean;
      sumSquaredDiff += diff * diff;
    }

    final variance = sumSquaredDiff / (data.length - 1);
    return variance > 0 ? sqrt(variance) : 0.0; // 제곱근 계산 추가!
  }

  /// Baseline 수동 설정 (초기 설정 또는 리셋)
  Future<void> setBaseline(double rmsBase, double freqBase) async {
    try {
      final db = await database;

      _currentRmsBase = rmsBase;
      _currentFreqBase = freqBase;

      final baseline = BaselineData(
        timestamp: DateTime.now(),
        rmsBase: rmsBase,
        freqBase: freqBase,
        sampleCount: 1,
      );

      await db.insert(DatabaseConstants.baselineTableName, baseline.toMap());

      print('✅ Baseline 수동 설정 완료:');
      print('   - RMS Base: ${rmsBase.toStringAsFixed(4)}');
      print('   - Freq Base: ${freqBase.toStringAsFixed(2)} Hz');
    } catch (e) {
      print('❌ Baseline 설정 오류: $e');
    }
  }

  /// 첫 측정값으로 baseline 초기화
  Future<void> initializeBaseline(double rms, double freq) async {
    print('\n🎯 첫 측정값으로 Baseline 초기화');
    await setBaseline(rms, freq);
  }

  /// Baseline 히스토리 조회
  Future<List<BaselineData>> getBaselineHistory(int limit) async {
    final db = await database;
    final result = await db.query(
      DatabaseConstants.baselineTableName,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return result.map((map) => BaselineData.fromMap(map)).toList();
  }

  /// 모든 baseline 삭제
  Future<void> clearBaseline() async {
    final db = await database;
    await db.delete(DatabaseConstants.baselineTableName);

    // 기본값으로 리셋
    _currentRmsBase = BaselineConstants.defaultRmsBase;
    _currentFreqBase = BaselineConstants.defaultFreqBase;

    print('🗑️ Baseline 초기화 완료 (기본값으로 리셋)');
  }

  /// 데이터베이스 닫기
  Future close() async {
    final db = await database;
    db.close();
  }
}
