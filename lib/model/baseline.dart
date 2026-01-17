/// Baseline 관리 클래스
/// DB_SCHEMA.md의 baseline 테이블 기반
library;

import 'database_helper.dart';
import 'config.dart';

class BaselineManager {
  static final BaselineManager instance = BaselineManager._init();

  // 현재 baseline 값 (메모리에 캐시)
  double _currentRmsBase = BaselineConstants.defaultRmsBase;
  double _currentFreqBase = BaselineConstants.defaultFreqBase;
  double _alpha = 0.05;
  double _beta = 0.05;

  // EMA 캘리브레이션 상태
  bool _isCalibrating = true;
  int _updateCount = 0;
  final List<double> _calibrationRms = [];
  final List<double> _calibrationFreq = [];

  // ML Phase 추적 (measure_sessions 테이블 기반)
  int _totalMeasurementCount = 0;
  int _totalWindowCount = 0;

  BaselineManager._init();

  /// 초기화 및 DB에서 로드
  Future<void> initialize() async {
    try {
      print('📊 Baseline 초기화...');
      final userState = await DatabaseHelper.instance.getUserState();

      if (userState != null) {
        final rms = userState['rms_base'] as double?;
        final freq = userState['freq_base'] as double?;
        if (rms != null && freq != null) {
          _currentRmsBase = rms;
          _currentFreqBase = freq;
        } else {
          // DB에 기준값이 없으면 내부값을 중립값(0.0)으로 두고 캘리브레이션 상태 유지
          _currentRmsBase = 0.0;
          _currentFreqBase = 0.0;
          _isCalibrating = true;
        }
        _alpha = 0.05;
        _beta = 0.05;

        print('✅ User State 로드 완료:');
        print('   - RMS Base: ${_currentRmsBase.toStringAsFixed(4)}');
        print('   - Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz');
      } else {
        print('⚠️ User State 레코드 없음, 기본값 사용');
      }

      // 측정 카운트 동기화
      await syncWithDatabase();
    } catch (e) {
      print('❌ Baseline 초기화 오류: $e');
    }
  }

  /// 현재 baseline 값 반환
  double get rmsBase => _currentRmsBase;
  double get freqBase => _currentFreqBase;
  double get alpha => _alpha;
  double get beta => _beta;
  bool get isCalibrating => _isCalibrating;
  int get updateCount => _updateCount;
  int get totalMeasurementCount => _totalMeasurementCount;
  int get totalWindowCount => _totalWindowCount;

  /// 현재 ML 모드 판단 (측정 세션 수 기준)
  MLMode getCurrentMLMode() {
    if (_totalMeasurementCount < MLPhaseConstants.emaPhaseThreshold) {
      return MLMode.ema;
    } else if (_totalMeasurementCount < MLPhaseConstants.hybridPhaseThreshold) {
      return MLMode.hybrid;
    } else {
      return MLMode.endToEnd;
    }
  }

  /// 다음 단계까지 남은 측정 수
  int getMeasurementsUntilNextPhase() {
    final currentMode = getCurrentMLMode();

    if (currentMode == MLMode.ema) {
      return MLPhaseConstants.emaPhaseThreshold - _totalMeasurementCount;
    } else if (currentMode == MLMode.hybrid) {
      return MLPhaseConstants.hybridPhaseThreshold - _totalMeasurementCount;
    } else {
      return 0; // 최종 단계
    }
  }

  /// 새로운 측정값으로 baseline 업데이트 (EMA 방식)
  Future<void> updateBaseline(double newRms, double newFreq) async {
    try {
      print('\n📈 Baseline 업데이트 시도...');
      print('   - 새 RMS: ${newRms.toStringAsFixed(4)}');
      print('   - 새 Freq: ${newFreq.toStringAsFixed(2)} Hz');

      final oldRmsBase = _currentRmsBase;
      final oldFreqBase = _currentFreqBase;

      // 캘리브레이션 단계 (첫 3회 측정)
      if (_isCalibrating) {
        _calibrationRms.add(newRms);
        _calibrationFreq.add(newFreq);

        print(
          '🎯 캘리브레이션 중... (${_calibrationRms.length}/${BaselineConstants.calibrationWindows})',
        );

        if (_calibrationRms.length >= BaselineConstants.calibrationWindows) {
          // 단순 평균으로 초기 baseline 설정
          _currentRmsBase =
              _calibrationRms.reduce((a, b) => a + b) / _calibrationRms.length;
          _currentFreqBase = _calibrationFreq.reduce((a, b) => a + b) /
              _calibrationFreq.length;
          _isCalibrating = false;

          print('✅ 캘리브레이션 완료!');
          print('   - 초기 RMS Base: ${_currentRmsBase.toStringAsFixed(4)}');
          print('   - 초기 Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz');
        }
      } else {
        // EMA 업데이트
        _currentRmsBase = BaselineConstants.alphaRms * newRms +
            (1 - BaselineConstants.alphaRms) * _currentRmsBase;
        _currentFreqBase = BaselineConstants.alphaFreq * newFreq +
            (1 - BaselineConstants.alphaFreq) * _currentFreqBase;

        print('✅ EMA 업데이트 완료:');
        print(
          '   - 이전 RMS Base: ${oldRmsBase.toStringAsFixed(4)} → 새 RMS Base: ${_currentRmsBase.toStringAsFixed(4)}',
        );
        print(
          '   - 이전 Freq Base: ${oldFreqBase.toStringAsFixed(2)} Hz → 새 Freq Base: ${_currentFreqBase.toStringAsFixed(2)} Hz',
        );
      }

      _updateCount++;

      // DB에 저장 (user_state 업데이트)
      await DatabaseHelper.instance.updateUserState(
        rmsBase: _currentRmsBase,
        freqBase: _currentFreqBase,
      );

      print('💾 User State 저장 완료');
      print('   - 업데이트 횟수: $_updateCount회');
      print('   - 현재 모드: ${getCurrentMLMode().displayName}');
    } catch (e) {
      print('❌ Baseline 업데이트 오류: $e');
    }
  }

  /// Baseline 초기화 (DB에서는 제거, 내부 상태는 초기값으로 리셋)
  Future<void> clearBaseline() async {
    try {
      _currentRmsBase = BaselineConstants.defaultRmsBase;
      _currentFreqBase = BaselineConstants.defaultFreqBase;
      _alpha = 0.05;
      _beta = 0.05;
      _updateCount = 0;
      _isCalibrating = true;
      _calibrationRms.clear();
      _calibrationFreq.clear();

      // DB의 기준값은 제거(null)하여 미설정 상태로 돌린다
      await DatabaseHelper.instance.updateUserState(
        rmsBase: null,
        freqBase: null,
      );

      print('🗑️ Baseline 초기화 완료 (DB 기준값 제거)');
    } catch (e) {
      print('❌ Baseline 초기화 오류: $e');
    }
  }

  /// DB 기록과 카운트 동기화
  Future<void> syncWithDatabase() async {
    try {
      print('\n🔄 DB와 Baseline 카운트 동기화 시도...');

      // 총 측정 로그 수 가져오기 (fatigue_dataset 집계)
      final logs = await DatabaseHelper.instance.getAllFatigueLogs();
      _totalMeasurementCount = logs.length;

      // 총 윈도우 수 계산 (모든 로그의 window_count 합산)
      _totalWindowCount = logs.fold<int>(
        0,
        (sum, log) => sum + (log['window_count'] as int? ?? 0),
      );

      print('✅ 카운트 동기화 완료');
      print('   - 총 측정 로그: $_totalMeasurementCount회');
      print('   - 총 윈도우: $_totalWindowCount개');
      print('   - 현재 ML 모드: ${getCurrentMLMode().displayName}');
    } catch (e) {
      print('❌ 카운트 동기화 실패: $e');
    }
  }

  /// 캘리브레이션 상태 메시지
  String getCalibrationMessage() {
    if (!_isCalibrating) return '개인화 완료';
    final remaining =
        BaselineConstants.calibrationWindows - _calibrationRms.length;
    return '캘리브레이션 중... (${_calibrationRms.length}/${BaselineConstants.calibrationWindows}, $remaining회 남음)';
  }
}
