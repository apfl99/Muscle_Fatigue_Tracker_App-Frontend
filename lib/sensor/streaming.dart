import 'dart:async';
import 'dart:math';
import 'package:motion_sensors/motion_sensors.dart';
import 'config.dart';
import 'filter.dart';
import 'calculateVal.dart';
import '../model/log.dart';
import '../model/baseline.dart';

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

  // 센서 데이터 수집 시작
  Future<bool> startSensor() async {
    print('\n🚀 센서 시작 시도');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    try {
      // 센서 설정 로그
      print('⚙️ 센서 설정:');
      print('   - 샘플링 레이트: ${SensorConfig.samplingRate} Hz');
      print('   - 윈도우 크기: ${SensorConfig.windowSeconds}초');
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

      // 윈도우 분석 시작
      _startWindowAnalysis();

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

  // 윈도우 분석 시작
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

  // 윈도우 단위 데이터 분석
  Future<void> _processSegment(List<double> data) async {
    print('\n🔬 데이터 분석 시작');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // 데이터 검증
    if (data.isEmpty || _filteredBuffer.isEmpty) {
      print('❌ 오류: 분석할 데이터가 없습니다');
      print('   - 원본 데이터: ${data.length}개');
      print('   - 필터링된 데이터: ${_filteredBuffer.length}개');
      return;
    }

    try {
      // 필터링된 데이터 복사
      final filteredData = List<double>.from(_filteredBuffer);
      _filteredBuffer.clear();

      print('✅ 데이터 검증 통과');
      print('   - 원본 샘플: ${data.length}개');
      print('   - 필터링된 샘플: ${filteredData.length}개');
      print('   - 샘플링 레이트: ${_currentSamplingRate.toStringAsFixed(1)} Hz');

      // 원본 데이터 통계
      double rawMean = _calculateMean(data);
      double rawRMS = _calculateRMS(data);
      double rawVariance = _calculateVariance(data, rawMean);

      // 필터링된 데이터 통계 (기본)
      double filteredMean = _calculateMean(filteredData);
      double filteredRMS = _calculateRMS(filteredData);
      double filteredVariance = _calculateVariance(filteredData, filteredMean);
      double filteredStdDev = sqrt(filteredVariance);

      print('\n📊 기본 통계:');
      print('   - 원본 RMS: ${rawRMS.toStringAsFixed(4)}');
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
      Map<String, dynamic> result = {
        'timestamp': DateTime.now(),
        'sampleCount': filteredData.length,
        // 원본 데이터
        'rawMean': rawMean,
        'rawRMS': rawRMS,
        'rawVariance': rawVariance,
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
        'windowSeconds': SensorConfig.windowSeconds,
      };

      // Baseline 가져오기
      final baselineManager = BaselineManager.instance;
      final rmsBase = baselineManager.rmsBase;
      final freqBase = baselineManager.freqBase;

      print('\n📊 현재 Baseline:');
      print('   - RMS Base: ${rmsBase.toStringAsFixed(4)}');
      print('   - Freq Base: ${freqBase.toStringAsFixed(2)} Hz');

      // 근피로도 점수 계산
      final fatigueScore = FatigueCalculator.calculateFatigue(
        rms: fatigueFeatures.rms,
        peakFreq: fatigueFeatures.peakFrequency,
        rmsBase: rmsBase,
        freqBase: freqBase,
      );
      final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);

      // Baseline 자동 업데이트 (Moving Average)
      await baselineManager.updateBaseline(
        fatigueFeatures.rms,
        fatigueFeatures.peakFrequency,
      );

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

      // 데이터베이스에 저장
      try {
        print('\n💾 데이터베이스 저장 시도...');
        final fatigueResult = FatigueResult(
          timestamp: result['timestamp'],
          rms: fatigueFeatures.rms,
          variance: fatigueFeatures.variance,
          peakFreq: fatigueFeatures.peakFrequency,
          meanPowerFreq: fatigueFeatures.meanPowerFrequency,
          medianFreq: fatigueFeatures.medianFrequency,
          fatigue: fatigueScore,
          sampleCount: filteredData.length,
          samplingRate: _currentSamplingRate,
        );

        final id = await FatigueDatabase.instance.insertResult(fatigueResult);
        result['dbId'] = id;

        // 총 저장된 레코드 수 확인
        final stats = await FatigueDatabase.instance.getStatistics();
        print('📊 총 저장된 측정 횟수: ${stats['count']}회');
      } catch (e) {
        print('❌ 데이터베이스 저장 실패: $e');
      }

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ 분석 완료\n');

      // 콜백 호출
      onAnalysisResult?.call(result);
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
  void stopSensor() {
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
