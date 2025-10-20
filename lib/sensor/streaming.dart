import 'dart:async';
import 'dart:math';
import 'package:motion_sensors/motion_sensors.dart';
import 'config.dart';
import 'filter.dart';
import 'calculateVal.dart';
import '../model/database_helper.dart';
import '../model/baseline.dart';
import '../model/measure_session.dart';
import '../model/window_feature.dart';
import '../model/config.dart' as model_config;
import '../model/ml.dart';

class SensorStreaming {
  // 가속도계 데이터 저장 (전체 기록용)
  List<double> accelX = [];
  List<double> accelY = [];
  List<double> accelZ = [];

  // 자이로스코프 데이터 저장 (전체 기록용)
  List<double> gyroX = [];
  List<double> gyroY = [];
  List<double> gyroZ = [];

  // 윈도우 버퍼 (분석용)
  final List<double> _windowBuffer = [];

  // 필터링된 데이터 버퍼 (필터링 후 값)
  final List<double> _filteredBuffer = [];

  // Adaptive Motion Filter
  final MotionFilterAdaptive _filter = MotionFilterAdaptive();

  // 스트림 구독 관리
  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;

  // 윈도우 타이머
  Timer? _windowTimer;

  // 분석 결과 콜백
  Function(Map<String, dynamic>)? onAnalysisResult;

  // 최신 필터링된 값
  double _latestFilteredValue = 0.0;
  double _currentSamplingRate = 0.0;

  // 마지막 윈도우 결과 (측정 완료 시 UI에 표시)
  Map<String, dynamic>? _lastWindowResult;

  // 현재 측정 세션 데이터 (측정 완료 시 DB에 저장)
  final List<Map<String, dynamic>> _currentSessionWindows = [];
  int _windowIndex = 0;

  // 센서 데이터 수집 시작
  Future<bool> startSensor() async {
    print('\n🚀 센서 시작 시도');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    try {
      final preset = SensorConfig.currentPreset;

      // 센서 설정 로그
      print('⚙️ 센서 설정:');
      print('   - 프리셋: ${preset.name}');
      print('   - 총 측정 시간: ${preset.totalSeconds}초');
      print('   - 윈도우 크기: ${preset.windowSeconds}초');
      print('   - Hop 크기: ${preset.hopSeconds}초');
      print('   - 예상 윈도우 수: ${preset.expectedWindows}개');
      print('   - 샘플링 레이트: ${SensorConfig.samplingRate} Hz');
      print('   - 업데이트 간격: ${SensorConfig.updateIntervalMicroseconds} μs');

      // 센서 업데이트 간격 설정 (Config에서 가져옴)
      motionSensors.accelerometerUpdateInterval =
          SensorConfig.updateIntervalMicroseconds;
      motionSensors.gyroscopeUpdateInterval =
          SensorConfig.updateIntervalMicroseconds;

      // 버퍼 초기화
      _windowBuffer.clear();
      _filteredBuffer.clear();
      _filter.reset();
      _currentSessionWindows.clear();
      _windowIndex = 0;
      print('✅ 버퍼 초기화 완료');

      int sensorEventCount = 0;

      // 가속도계 이벤트 수집
      _accelSubscription = motionSensors.accelerometer.listen(
        (event) {
          try {
            sensorEventCount++;

            // 전체 데이터 저장
            accelX.add(event.x);
            accelY.add(event.y);
            accelZ.add(event.z);

            // 필터 적용 (중력 제거 + Band-pass)
            final now = DateTime.now().microsecondsSinceEpoch;
            final filtered = _filter.process(event.x, event.y, event.z, now);

            // 필터링된 값 저장
            _latestFilteredValue = filtered;
            _currentSamplingRate = _filter.fs;
            _filteredBuffer.add(filtered);

            // 원본 크기(magnitude)도 계산 (비교용)
            double magnitude = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            _windowBuffer.add(magnitude);

            // 처음 몇 개의 이벤트만 로그
            if (sensorEventCount <= 3) {
              print('📥 센서 이벤트 #$sensorEventCount:');
              print(
                '   - Raw: (${event.x.toStringAsFixed(2)}, ${event.y.toStringAsFixed(2)}, ${event.z.toStringAsFixed(2)})',
              );
              print('   - Filtered: ${filtered.toStringAsFixed(4)}');
            }
          } catch (e) {
            print('❌ 센서 데이터 처리 오류: $e');
          }
        },
        onError: (error) {
          print('❌ 가속도계 에러: $error');
        },
      );

      // 자이로스코프 이벤트 수집
      _gyroSubscription = motionSensors.gyroscope.listen(
        (event) {
          gyroX.add(event.x);
          gyroY.add(event.y);
          gyroZ.add(event.z);
        },
        onError: (error) {
          print('❌ 자이로스코프 에러: $error');
        },
      );

      // 슬라이딩 윈도우 분석 시작
      _startSlidingWindowAnalysis();

      print('✅ 센서 측정 시작 성공');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      return true;
    } catch (e, stackTrace) {
      print('❌ 센서 시작 실패: $e');
      print('스택 트레이스: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      return false;
    }
  }

  // 슬라이딩 윈도우 분석 시작
  void _startSlidingWindowAnalysis() {
    final preset = SensorConfig.currentPreset;
    print('📊 슬라이딩 윈도우 분석 시작');
    print('   - 윈도우 크기: ${preset.windowSeconds}초');
    print('   - Hop 크기: ${preset.hopSeconds}초');

    // Hop 간격마다 윈도우 분석 수행
    _windowTimer = Timer.periodic(
      Duration(milliseconds: (preset.hopSeconds * 1000).toInt()),
      (timer) {
        print('⏰ 슬라이딩 윈도우 타이머 실행 (${timer.tick}번째)');

        // 필요한 샘플 수 계산
        final windowSamples = preset.getWindowSamples(_currentSamplingRate);

        // 데이터 누락 검증
        if (_filteredBuffer.length < windowSamples) {
          print(
            '⏳ 대기 중: 윈도우 크기($windowSamples개)에 도달하지 않음 (현재: ${_filteredBuffer.length}개)',
          );
          return;
        }

        // 윈도우 크기만큼 데이터 추출
        final windowData = _filteredBuffer.sublist(0, windowSamples);

        // Hop 크기만큼 데이터 제거
        final hopSamples = preset.getHopSamples(_currentSamplingRate);
        _filteredBuffer.removeRange(
          0,
          hopSamples.clamp(0, _filteredBuffer.length),
        );

        print('✅ 윈도우 추출 완료');
        print('   - 윈도우 샘플: ${windowData.length}개');
        print('   - Hop 샘플: $hopSamples개 제거');
        print('   - 남은 샘플: ${_filteredBuffer.length}개');

        // 분석 수행
        _processSegment(windowData);
      },
    );
  }

  // 기존 윈도우 분석 (사용하지 않음, 하위 호환성 유지)
  /*
  void _startWindowAnalysis() {
    print('📊 윈도우 분석 시작 (주기: ${SensorConfig.windowSeconds}초)');

    _windowTimer = Timer.periodic(
      Duration(seconds: SensorConfig.windowSeconds),
      (timer) {
        print('⏰ 윈도우 타이머 실행');

        // 데이터 누락 검증
        if (_windowBuffer.isEmpty) {
          print('❌ 오류: 윈도우 버퍼가 비어있습니다');
          print('   - 원본 버퍼: ${_windowBuffer.length}개');
          print('   - 필터 버퍼: ${_filteredBuffer.length}개');
          return;
        }

        if (_filteredBuffer.isEmpty) {
          print('❌ 오류: 필터링된 버퍼가 비어있습니다');
          print('   - 원본 버퍼: ${_windowBuffer.length}개');
          print('   - 필터 버퍼: ${_filteredBuffer.length}개');
          return;
        }

        // 샘플 수 검증
        final expectedSamples =
            (_currentSamplingRate * SensorConfig.windowSeconds).toInt();
        final actualSamples = _filteredBuffer.length;
        final sampleRatio = actualSamples / expectedSamples;

        print('📈 샘플 수 검증:');
        print(
          '   - 예상: $expectedSamples개 (${_currentSamplingRate.toStringAsFixed(1)} Hz × ${SensorConfig.windowSeconds}초)',
        );
        print('   - 실제: $actualSamples개');
        print('   - 비율: ${(sampleRatio * 100).toStringAsFixed(1)}%');

        if (sampleRatio < 0.5) {
          print('⚠️ 경고: 샘플 수가 예상의 50% 미만입니다. 센서가 제대로 작동하지 않을 수 있습니다.');
        }

        // 현재까지 수집된 데이터를 복사
        final segment = List<double>.from(_windowBuffer);

        // 버퍼 초기화 (다음 윈도우를 위해)
        _windowBuffer.clear();

        // 분석 수행
        _processSegment(segment);
      },
    );
  }
  // */

  // 윈도우 단위 데이터 분석
  Future<void> _processSegment(List<double> segmentData) async {
    print('\n🔬 데이터 분석 시작');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // 데이터 검증
    if (segmentData.isEmpty) {
      print('❌ 오류: 분석할 데이터가 없습니다');
      print('   - 윈도우 데이터: ${segmentData.length}개');
      return;
    }

    try {
      // 슬라이딩 윈도우로 전달받은 데이터 사용
      final filteredData = segmentData;

      print('✅ 데이터 검증 통과');
      print('   - 필터링된 샘플: ${filteredData.length}개');
      print('   - 샘플링 레이트: ${_currentSamplingRate.toStringAsFixed(1)} Hz');

      // 필터링된 데이터 통계 (기본)
      double filteredMean = _calculateMean(filteredData);
      double filteredRMS = _calculateRMS(filteredData);
      double filteredVariance = _calculateVariance(filteredData, filteredMean);
      double filteredStdDev = sqrt(filteredVariance);

      print('\n📊 기본 통계:');
      print('   - 필터링 RMS: ${filteredRMS.toStringAsFixed(4)}');
      print('   - 필터링 분산: ${filteredVariance.toStringAsFixed(4)}');

      // 근피로도 특징 계산 (FFT 포함)
      print('\n🔍 FFT 분석 중...');
      final fatigueFeatures = calculateFatigueFeatures(
        filteredData,
        _currentSamplingRate,
      );

      // 최대/최소값 (필터링된 데이터)
      double maxVal = filteredData.reduce((a, b) => a > b ? a : b);
      double minVal = filteredData.reduce((a, b) => a < b ? a : b);

      // 분석 결과 구성
      final preset = SensorConfig.currentPreset;
      Map<String, dynamic> result = {
        'timestamp': DateTime.now(),
        'sampleCount': filteredData.length,
        // 필터링된 데이터 (기본)
        'filteredMean': filteredMean,
        'filteredRMS': filteredRMS,
        'filteredVariance': filteredVariance,
        'filteredStdDev': filteredStdDev,
        // 근피로도 특징 (FFT 기반)
        'fatigueRMS': fatigueFeatures.rms,
        'fatigueVariance': fatigueFeatures.variance,
        'peakFreq': fatigueFeatures.peakFrequency,
        'meanPowerFreq': fatigueFeatures.meanPowerFrequency,
        'medianFreq': fatigueFeatures.medianFrequency,
        'fatigueStdDev': fatigueFeatures.stdDev,
        // 기타
        'max': maxVal,
        'min': minVal,
        'samplingRate': _currentSamplingRate,
        'windowSeconds': preset.windowSeconds,
        'hopSeconds': preset.hopSeconds,
        'presetName': preset.name,
      };

      // Baseline 가져오기
      final baselineManager = BaselineManager.instance;
      final rmsBase = baselineManager.rmsBase;
      final freqBase = baselineManager.freqBase;
      final currentMLMode = baselineManager.getCurrentMLMode();

      print('\n📊 현재 Baseline:');
      print('   - RMS Base: ${rmsBase.toStringAsFixed(4)}');
      print('   - Freq Base: ${freqBase.toStringAsFixed(2)} Hz');
      print('   - ML Mode: ${currentMLMode.displayName}');

      // ML 모드별 근피로도 점수 계산
      double fatigueScore;

      switch (currentMLMode) {
        case model_config.MLMode.ema:
          // Phase 1: EMA 기반 계산
          print('\n🔵 Phase 1: EMA 개인화 모드');
          fatigueScore = FatigueCalculator.calculateFatigue(
            rms: fatigueFeatures.rms,
            peakFreq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
          );
          break;

        case model_config.MLMode.hybrid:
          // Phase 2: Hybrid (EMA + ML)
          print('\n🟡 Phase 2: Hybrid 보정 모드');
          // 이전 피로도 가져오기 (없으면 1.0)
          double prevFatigue = 1.0;
          try {
            final recentSessions =
                await DatabaseHelper.instance.getRecentMeasureSessions(1);
            if (recentSessions.isNotEmpty) {
              prevFatigue = recentSessions.first['fatigue'] as double? ?? 1.0;
            }
          } catch (e) {
            print('⚠️ 이전 피로도 조회 실패: $e');
          }

          fatigueScore = await calculateHybridFatigue(
            rms: fatigueFeatures.rms,
            freq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
            prevFatigue: prevFatigue,
          );
          break;

        case model_config.MLMode.endToEnd:
          // Phase 3: End-to-End ML
          print('\n🟢 Phase 3: End-to-End ML 모드');
          final mlFatigue = await calculateEndToEndFatigue(
            windowData: filteredData,
            rms: fatigueFeatures.rms,
            freq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
          );
          fatigueScore = mlFatigue ?? 1.0; // null이면 1.0 기본값
          break;
      }

      final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);

      result['fatigueScore'] = fatigueScore;
      result['fatigueLevel'] = fatigueLevel;

      print('\n💪 근피로도 특징:');
      print('   - RMS: ${fatigueFeatures.rms.toStringAsFixed(4)}');
      print('   - Variance: ${fatigueFeatures.variance.toStringAsFixed(4)}');
      print(
        '   - Peak Freq: ${fatigueFeatures.peakFrequency.toStringAsFixed(2)} Hz',
      );
      print(
        '   - Mean Power Freq: ${fatigueFeatures.meanPowerFrequency.toStringAsFixed(2)} Hz',
      );
      print(
        '   - Median Freq: ${fatigueFeatures.medianFrequency.toStringAsFixed(2)} Hz',
      );
      print('   - StdDev: ${fatigueFeatures.stdDev.toStringAsFixed(4)}');
      print(
        '   - Zero Crossing: ${fatigueFeatures.zeroCrossing.toStringAsFixed(2)} Hz',
      );
      print(
        '   - 🎯 피로도 점수: ${fatigueScore.toStringAsFixed(2)} ($fatigueLevel)',
      );

      print('\n📈 데이터 범위:');
      print('   - 최대값: ${maxVal.toStringAsFixed(4)}');
      print('   - 최소값: ${minVal.toStringAsFixed(4)}');

      // 현재 측정 세션에 윈도우 데이터 추가
      final windowData = {
        'window_index': _windowIndex,
        'rms': fatigueFeatures.rms,
        'freq': fatigueFeatures.peakFrequency,
        'fatigue': fatigueScore,
        'variance': fatigueFeatures.variance,
        'mean_power_freq': fatigueFeatures.meanPowerFrequency,
        'median_freq': fatigueFeatures.medianFrequency,
        'sample_count': filteredData.length,
        'timestamp': result['timestamp'],
      };
      _currentSessionWindows.add(windowData);
      _windowIndex++;

      print('✅ 윈도우 데이터 세션에 추가 (인덱스: ${_windowIndex - 1})');

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ 윈도우 분석 완료\n');

      // 마지막 윈도우 결과 저장 (측정 완료 시 UI에 표시)
      _lastWindowResult = result;

      // 윈도우마다 콜백 호출하지 않음 (측정 완료 시에만)
      // onAnalysisResult?.call(result);
    } catch (e, stackTrace) {
      print('❌ 분석 중 오류 발생: $e');
      print('스택 트레이스: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    }
  }

  // 평균 계산
  double _calculateMean(List<double> data) {
    if (data.isEmpty) return 0.0;
    return data.reduce((a, b) => a + b) / data.length;
  }

  // RMS (Root Mean Square) 계산
  double _calculateRMS(List<double> data) {
    if (data.isEmpty) return 0.0;
    double sumOfSquares = data.fold(0.0, (sum, val) => sum + val * val);
    return sqrt(sumOfSquares / data.length);
  }

  // 분산 계산
  double _calculateVariance(List<double> data, double mean) {
    if (data.isEmpty) return 0.0;
    double sumOfSquaredDiff = data.fold(
      0.0,
      (sum, val) => sum + pow(val - mean, 2),
    );
    return sumOfSquaredDiff / data.length;
  }

  // 센서 데이터 수집 중지
  Future<void> stopSensor() async {
    print('\n🛑 센서 측정 중지');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _windowTimer?.cancel();

    _accelSubscription = null;
    _gyroSubscription = null;
    _windowTimer = null;

    print('📊 최종 통계:');
    print('   - 총 수집된 샘플: ${accelX.length}개');
    print('   - 윈도우 버퍼: ${_windowBuffer.length}개');
    print('   - 필터링된 버퍼: ${_filteredBuffer.length}개');
    print('   - 최종 샘플링 레이트: ${_currentSamplingRate.toStringAsFixed(1)} Hz');

    // 측정 완료: 세션 데이터를 DB에 저장
    if (_currentSessionWindows.isNotEmpty) {
      print('🎯 측정 세션 저장 시작...');
      print('   - 총 윈도우 수: ${_currentSessionWindows.length}개');

      try {
        // 세션 평균값 계산
        final avgRms = _currentSessionWindows
                .map((w) => w['rms'] as double)
                .reduce((a, b) => a + b) /
            _currentSessionWindows.length;

        final avgFreq = _currentSessionWindows
                .map((w) => w['freq'] as double)
                .reduce((a, b) => a + b) /
            _currentSessionWindows.length;

        final avgFatigue = _currentSessionWindows
                .map((w) => w['fatigue'] as double)
                .reduce((a, b) => a + b) /
            _currentSessionWindows.length;

        // 현재 ML 모드 가져오기
        final currentMLMode = BaselineManager.instance.getCurrentMLMode();

        // MeasureSession 생성
        final session = MeasureSession(
          timestamp: DateTime.now(),
          rms: avgRms,
          freq: avgFreq,
          fatigue: avgFatigue,
          mode: currentMLMode.name,
          windowCount: _currentSessionWindows.length,
          synced: 0,
        );

        // DB에 저장
        final sessionId =
            await DatabaseHelper.instance.insertMeasureSession(session.toMap());
        print('✅ 측정 세션 저장 완료 (ID: $sessionId)');
        print('   - 평균 피로도: ${avgFatigue.toStringAsFixed(2)}');
        print('   - 평균 RMS: ${avgRms.toStringAsFixed(4)}');
        print('   - 평균 Freq: ${avgFreq.toStringAsFixed(2)} Hz');

        // Window Features 저장 (ML 학습용)
        for (var window in _currentSessionWindows) {
          final feature = WindowFeature(
            sessionId: sessionId,
            windowIndex: window['window_index'] as int,
            rms: window['rms'] as double,
            freq: window['freq'] as double,
            fatiguePred: window['fatigue'] as double,
          );
          await DatabaseHelper.instance.insertWindowFeature(feature.toMap());
        }
        print('✅ Window Features 저장 완료 (${_currentSessionWindows.length}개)');

        // Baseline 업데이트 (EMA 방식)
        final baselineManager = BaselineManager.instance;
        if (currentMLMode != model_config.MLMode.endToEnd) {
          await baselineManager.updateBaseline(avgRms, avgFreq);
          print('✅ Baseline 업데이트 완료');
        }

        // DB와 동기화
        await baselineManager.syncWithDatabase();

        // User Stats 재계산 (최근 5회 기준)
        await DatabaseHelper.instance.recalculateUserStats(n: 5);
        print('✅ User Stats 재계산 완료');

        // UI에 결과 전달
        if (_lastWindowResult != null) {
          final sessionAvgResult =
              Map<String, dynamic>.from(_lastWindowResult!);
          sessionAvgResult['fatigueScore'] = avgFatigue;
          sessionAvgResult['fatigueRMS'] = avgRms;
          sessionAvgResult['fatiguePeakFreq'] = avgFreq;
          sessionAvgResult['fatigueLevel'] =
              FatigueCalculator.getFatigueLevel(avgFatigue);
          onAnalysisResult?.call(sessionAvgResult);
        }
      } catch (e, stackTrace) {
        print('❌ 측정 세션 저장 실패: $e');
        print('스택 트레이스: $stackTrace');
      }
    } else {
      print('⚠️ 저장할 측정 데이터가 없습니다');
    }

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  // 수집된 데이터 초기화
  void clearData() {
    accelX.clear();
    accelY.clear();
    accelZ.clear();
    gyroX.clear();
    gyroY.clear();
    gyroZ.clear();
    _windowBuffer.clear();
    _filteredBuffer.clear();
    _filter.reset();
    _latestFilteredValue = 0.0;
    _currentSamplingRate = 0.0;
    _lastWindowResult = null;
    _currentSessionWindows.clear();
    _windowIndex = 0;
  }

  // 수집된 데이터 개수 확인
  int getDataCount() {
    return accelX.length;
  }

  // 윈도우 버퍼 크기 확인
  int getWindowBufferSize() {
    return _windowBuffer.length;
  }

  // 최신 필터링된 값 가져오기
  double getLatestFilteredValue() {
    return _latestFilteredValue;
  }

  // 현재 샘플링 레이트 가져오기
  double getCurrentSamplingRate() {
    return _currentSamplingRate;
  }

  // 리소스 정리
  void dispose() {
    stopSensor();
    clearData();
  }

  // 최신 가속도계 값 가져오기
  Map<String, double>? getLatestAccelData() {
    if (accelX.isEmpty) return null;
    return {
      'x': accelX.last,
      'y': accelY.last,
      'z': accelZ.last,
    };
  }

  // 최신 자이로스코프 값 가져오기
  Map<String, double>? getLatestGyroData() {
    if (gyroX.isEmpty) return null;
    return {
      'x': gyroX.last,
      'y': gyroY.last,
      'z': gyroZ.last,
    };
  }

  // 평균 가속도 계산
  Map<String, double>? getAverageAccelData() {
    if (accelX.isEmpty) return null;
    return {
      'x': accelX.reduce((a, b) => a + b) / accelX.length,
      'y': accelY.reduce((a, b) => a + b) / accelY.length,
      'z': accelZ.reduce((a, b) => a + b) / accelZ.length,
    };
  }
}
