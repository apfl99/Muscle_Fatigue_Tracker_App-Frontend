import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'config.dart';
import 'filter.dart';
import 'calculateVal.dart';
import '../model/database_helper.dart';
import '../model/baseline.dart';
import '../model/measure_session.dart';
import '../model/config.dart' as model_config;
import '../model/ml.dart';
import '../worker/worker_manager.dart';

class SensorStreaming {
  // Raw 데이터 버퍼
  List<double> accelX = [];
  List<double> accelY = [];
  List<double> accelZ = [];
  List<double> gyroX = [];
  List<double> gyroY = [];
  List<double> gyroZ = [];

  // 분석용 버퍼
  final List<double> _windowBuffer = [];
  final List<double> _filteredBuffer = [];

  final MotionFilterAdaptive _filter = MotionFilterAdaptive();

  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;
  Timer? _windowTimer;

  int _measurementCount = 0;
  Function(Map<String, dynamic>)? onAnalysisResult;

  double _currentSamplingRate = 0.0;
  int? _lastSampleTime;

  // 측정 세션 데이터
  final List<Map<String, dynamic>> _currentSessionWindows = [];
  int _windowIndex = 0;
  Map<String, dynamic>? _lastWindowResult;

  // 윈도우 생성 카운터
  int _windowCount = 0;

  // 기준값 측정 등 로그/업로드에서 제외해야 하는 세션 플래그
  bool _excludeFromLogging = false;
  // 세션당 Baseline 중복 업데이트 방지
  bool _baselineUpdatedThisStop = false;

  void setExcludeFromLogging(bool exclude) {
    _excludeFromLogging = exclude;
  }

  // 샘플링 안정화 설정
  static const double targetRate = 50.0; // 목표 50Hz
  static const double tolerance = 0.1; // ±10% 허용

  // 센서 시작
  Future<bool> startSensor() async {
    print('\n🚀 센서 시작 시도');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _measurementCount = 0;
    print('📊 측정 횟수 초기화: $_measurementCount회');

    try {
      print('⚙️ 센서 설정:');
      print('   - 총 측정 시간: ${SensorConfig.totalSeconds}초');
      print('   - 윈도우 크기: ${SensorConfig.windowSeconds}초');
      print('   - Hop 크기: ${SensorConfig.hopSeconds}초');
      print('   - 예상 윈도우 수: ${SensorConfig.expectedWindows}개');
      print('   - 샘플링 레이트(목표): $targetRate Hz');

      _windowBuffer.clear();
      _filteredBuffer.clear();
      _filter.reset();
      _currentSessionWindows.clear();
      _windowIndex = 0;
      _windowCount = 0;

      int sensorEventCount = 0;

      // RxDart로 주기 제한 (20ms → 약 50Hz)
      _accelSubscription = accelerometerEventStream()
          .throttleTime(const Duration(milliseconds: 20))
          .listen(
        (event) {
          try {
            sensorEventCount++;
            final now = DateTime.now().microsecondsSinceEpoch;

            // 샘플링 레이트 계산 (EMA 방식으로 안정화 - 가속화)
            if (_lastSampleTime != null) {
              final dt = (now - _lastSampleTime!) / 1e6;
              if (dt > 0) {
                final instantRate = 1 / dt;
                // EMA로 부드럽게 업데이트 (alpha = 0.2로 가속화)
                if (_currentSamplingRate > 0) {
                  _currentSamplingRate =
                      0.8 * _currentSamplingRate + 0.2 * instantRate;
                } else {
                  _currentSamplingRate = instantRate;
                }
              }
            }
            _lastSampleTime = now;

            // 원시 데이터 저장
            accelX.add(event.x);
            accelY.add(event.y);
            accelZ.add(event.z);

            // 필터 처리
            final filtered = _filter.process(event.x, event.y, event.z, now);
            _filteredBuffer.add(filtered);

            // Magnitude 계산
            final mag =
                sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
            _windowBuffer.add(mag);

            if (sensorEventCount <= 10) {
              print(
                  '📥 센서 이벤트 #$sensorEventCount: Raw=(${event.x.toStringAsFixed(2)}, ${event.y.toStringAsFixed(2)}, ${event.z.toStringAsFixed(2)}), '
                  'Filtered=${filtered.toStringAsFixed(4)}');
            }

            // 필터링된 데이터가 모두 0에 가까운지 확인
            if (sensorEventCount % 50 == 0) {
              print('🔍 필터링 상태 체크:');
              print(
                '   - Raw magnitude: ${sqrt(event.x * event.x + event.y * event.y + event.z * event.z).toStringAsFixed(4)}',
              );
              print('   - Filtered value: ${filtered.toStringAsFixed(4)}');
              print('   - Filtered buffer length: ${_filteredBuffer.length}');
              if (_filteredBuffer.isNotEmpty) {
                final startIndex = _filteredBuffer.length - 5;
                final recentValues =
                    _filteredBuffer.sublist(startIndex < 0 ? 0 : startIndex);
                print(
                  '   - Recent filtered values: ${recentValues.map((v) => v.toStringAsFixed(4)).join(', ')}',
                );
              }
            }
          } catch (e) {
            print('❌ 센서 데이터 처리 오류: $e');
          }
        },
        onError: (error) => print('❌ 가속도계 에러: $error'),
      );

      _gyroSubscription = gyroscopeEventStream()
          .throttleTime(const Duration(milliseconds: 20))
          .listen(
        (event) {
          gyroX.add(event.x);
          gyroY.add(event.y);
          gyroZ.add(event.z);
        },
        onError: (error) => print('❌ 자이로스코프 에러: $error'),
      );

      _startSlidingWindowAnalysis();
      print('✅ 센서 측정 시작 성공');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      return true;
    } catch (e, st) {
      print('❌ 센서 시작 실패: $e');
      print('스택 트레이스: $st');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      return false;
    }
  }

  // 슬라이딩 윈도우 분석
  void _startSlidingWindowAnalysis() {
    print('📊 슬라이딩 윈도우 분석 시작');
    print(
      '   - 윈도우 크기: ${SensorConfig.windowSeconds}초, Hop 크기: ${SensorConfig.hopSeconds}초',
    );
    print('   - 예상 윈도우 수: ${SensorConfig.expectedWindows}개');
    print('   - 타이머 주기: ${(SensorConfig.hopSeconds * 1000).toInt()}ms');

    _windowTimer = Timer.periodic(
      Duration(milliseconds: (SensorConfig.hopSeconds * 1000).toInt()),
      (timer) {
        print('⏰ 슬라이딩 윈도우 타이머 실행 (${timer.tick}번째)');

        // 실제 샘플링 레이트가 0이면 기본값 사용
        final effectiveSamplingRate =
            _currentSamplingRate > 0 ? _currentSamplingRate : 50.0;
        final windowSamples =
            SensorConfig.getWindowSamples(effectiveSamplingRate);

        print(
          '📊 윈도우 요구사항: $windowSamples개 샘플 (${effectiveSamplingRate.toStringAsFixed(1)} Hz)',
        );
        print('📊 현재 버퍼: ${_filteredBuffer.length}개 샘플');

        // 윈도우 생성 조건 완화: 최소 50% 이상이면 생성
        final minRequiredSamples = (windowSamples * 0.5).round();
        if (_filteredBuffer.length < minRequiredSamples) {
          print(
            '⏳ 대기 중: ${_filteredBuffer.length}/$minRequiredSamples (최소 요구량)',
          );
          return;
        }

        // 실제 사용할 샘플 수 (버퍼 크기에 맞춤)
        final actualSamples = _filteredBuffer.length < windowSamples
            ? _filteredBuffer.length
            : windowSamples;

        print('📊 실제 사용 샘플: $actualSamples개');

        final windowData = _filteredBuffer.sublist(0, actualSamples);
        final hopSamples = SensorConfig.getHopSamples(effectiveSamplingRate);
        final actualHopSamples = hopSamples.clamp(0, _filteredBuffer.length);
        _filteredBuffer.removeRange(0, actualHopSamples);

        print('📊 Hop 제거: $actualHopSamples개 샘플');

        _windowCount++;
        print(
          '✅ 윈도우 추출 완료 (${windowData.length} samples) - 총 $_windowCount개 윈도우',
        );
        _processSegment(windowData);
      },
    );
  }

  // 윈도우 분석
  Future<void> _processSegment(List<double> segmentData) async {
    print('\n🔬 데이터 분석 시작');
    if (segmentData.isEmpty) {
      print('❌ 오류: 분석할 데이터 없음');
      return;
    }

    try {
      final filteredData = segmentData;
      print(
        '✅ 데이터 검증 통과 (${filteredData.length} samples @ ${_currentSamplingRate.toStringAsFixed(1)} Hz)',
      );

      // 필터링된 데이터의 통계 확인
      final mean = _calculateMean(filteredData);
      final rms = _calculateRMS(filteredData);
      final variance = _calculateVariance(filteredData, mean);

      print(
        '📊 필터링된 데이터 통계: RMS=${rms.toStringAsFixed(4)}, VAR=${variance.toStringAsFixed(4)}',
      );

      // 필터링된 데이터가 모두 0에 가까우면 원시 magnitude 사용
      List<double> analysisData = filteredData;
      if (rms < 0.001) {
        print('⚠️ 필터링된 데이터가 너무 작음, 원시 magnitude 사용');
        // 윈도우 크기만큼 원시 magnitude 데이터 추출
        final windowSamples = segmentData.length;
        final startIndex = _windowBuffer.length - windowSamples;

        print('🔍 원시 데이터 추출 디버그:');
        print('   - windowSamples: $windowSamples');
        print('   - _windowBuffer.length: ${_windowBuffer.length}');
        print('   - startIndex: $startIndex');

        if (startIndex >= 0 &&
            startIndex < _windowBuffer.length &&
            windowSamples > 0) {
          try {
            analysisData =
                _windowBuffer.sublist(startIndex, _windowBuffer.length);
            final rawMean = _calculateMean(analysisData);
            final rawRms = _calculateRMS(analysisData);
            print(
              '📊 원시 magnitude 통계: RMS=${rawRms.toStringAsFixed(4)}, VAR=${_calculateVariance(analysisData, rawMean).toStringAsFixed(4)}',
            );
          } catch (e) {
            print('❌ 원시 데이터 추출 실패: $e, 필터링된 데이터 사용');
            analysisData = filteredData;
          }
        } else {
          print('❌ 원시 데이터 인덱스 오류, 필터링된 데이터 사용');
          analysisData = filteredData;
        }
      }

      // 샘플링 레이트가 유효하지 않으면 기본값 사용
      final effectiveSamplingRate =
          _currentSamplingRate > 0 ? _currentSamplingRate : 50.0;
      print(
        '📊 주파수 분석용 샘플링 레이트: ${effectiveSamplingRate.toStringAsFixed(1)} Hz',
      );

      final fatigueFeatures =
          calculateFatigueFeatures(analysisData, effectiveSamplingRate);
      final baseline = BaselineManager.instance;
      final rmsBase = baseline.rmsBase;
      final freqBase = baseline.freqBase;
      final mode = baseline.getCurrentMLMode();

      double fatigueScore;
      switch (mode) {
        case model_config.MLMode.ema:
          fatigueScore = FatigueCalculator.calculateFatigue(
            rms: fatigueFeatures.rms,
            peakFreq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
          );
          break;
        case model_config.MLMode.hybrid:
          double prevFatigue = 1.0;
          try {
            final logs =
                await DatabaseHelper.instance.getRecentFatigueLogs(limit: 1);
            if (logs.isNotEmpty) prevFatigue = logs.first['fatigue'] ?? 1.0;
          } catch (_) {}
          fatigueScore = await calculateHybridFatigue(
            rms: fatigueFeatures.rms,
            freq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
            prevFatigue: prevFatigue,
          );
          break;
        case model_config.MLMode.endToEnd:
          fatigueScore = (await calculateEndToEndFatigue(
                windowData: filteredData,
                rms: fatigueFeatures.rms,
                freq: fatigueFeatures.peakFrequency,
                rmsBase: rmsBase,
                freqBase: freqBase,
              )) ??
              1.0;
          break;
      }

      final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);
      print(
        '💪 근피로도 계산 완료 → 점수: ${fatigueScore.toStringAsFixed(2)} ($fatigueLevel)',
      );

      // 🔎 분석 결과 상세 로그 (정확도 확인용)
      print('🔎 분석 결과 → '
          'RMS=${fatigueFeatures.rms.toStringAsFixed(4)}, '
          'VAR=${fatigueFeatures.variance.toStringAsFixed(4)}, '
          'FREQ=${fatigueFeatures.peakFrequency.toStringAsFixed(2)} Hz');

      // 윈도우 결과를 세션에 저장
      final windowData = {
        'window_index': _windowIndex,
        'rms': fatigueFeatures.rms,
        'freq': fatigueFeatures.peakFrequency,
        'fatigue': fatigueScore,
        'variance': fatigueFeatures.variance,
        'mean_power_freq': fatigueFeatures.meanPowerFrequency,
        'median_freq': fatigueFeatures.medianFrequency,
        'sample_count': analysisData.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _currentSessionWindows.add(windowData);
      _windowIndex++;

      // 마지막 윈도우 결과 저장
      _lastWindowResult = {
        'fatigueScore': fatigueScore,
        'fatigueLevel': fatigueLevel,
        'rms': fatigueFeatures.rms,
        'peakFreq': fatigueFeatures.peakFrequency,
        'fatigueRMS': fatigueFeatures.rms,
        'fatigueVariance': fatigueFeatures.variance,
        'timestamp': DateTime.now(),
      };
    } catch (e, st) {
      print('❌ 분석 중 오류: $e');
      print(st);
    }
  }

  double _calculateMean(List<double> d) =>
      d.isEmpty ? 0.0 : d.reduce((a, b) => a + b) / d.length;
  double _calculateRMS(List<double> d) =>
      d.isEmpty ? 0.0 : sqrt(d.fold(0.0, (s, v) => s + v * v) / d.length);
  double _calculateVariance(List<double> d, double m) =>
      d.isEmpty ? 0.0 : d.fold(0.0, (s, v) => s + pow(v - m, 2)) / d.length;

  // 센서 중지
  Future<void> stopSensor() async {
    print('\n🛑 센서 측정 중지');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    await _accelSubscription?.cancel();
    await _gyroSubscription?.cancel();
    _windowTimer?.cancel();

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
        if (_excludeFromLogging) {
          print('⛔️ 이번 세션은 로그/업로드에서 제외됩니다 (baseline 측정 등)');
          // 제외 플래그는 1회성으로 사용
          _excludeFromLogging = false;
          return;
        }

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

        // 첫 측정/기준값 상태 확인
        final isFirstMeasurement =
            await DatabaseHelper.instance.isFirstMeasurement();
        final hasBaseline = await DatabaseHelper.instance.hasBaseline();

        if (isFirstMeasurement && !hasBaseline) {
          // 기준값 미설정 상태의 첫 측정은 기록/업로드 제외 (baseline 전용)
          print('📊 첫 측정 + 기준값 미설정 → 기록/업로드 제외 (baseline 전용)');
          print('   - 평균 RMS: ${avgRms.toStringAsFixed(4)}');
          print('   - 평균 Freq: ${avgFreq.toStringAsFixed(2)} Hz');
        } else {
          // 일반 측정은 기존대로 저장
          // 현재 ML 모드 가져오기
          final currentMLMode = BaselineManager.instance.getCurrentMLMode();

          // 세션 ID 생성 (timestamp 기반)
          final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';

          // fatigue_logs에 저장
          await DatabaseHelper.instance.insertFatigueLog(
            userId: 'local_user',
            sessionId: sessionId,
            measureDate: DateTime.now(),
            rms: avgRms,
            freq: avgFreq,
            fatigue: avgFatigue,
            mode: currentMLMode.name,
            windowCount: _currentSessionWindows.length,
          );
          print('✅ 피로도 로그 저장 완료 (ID: $sessionId)');
          print('   - 평균 피로도: ${avgFatigue.toStringAsFixed(2)}');
          print('   - 평균 RMS: ${avgRms.toStringAsFixed(4)}');
          print('   - 평균 Freq: ${avgFreq.toStringAsFixed(2)} Hz');

          // Window Features를 temp_measurements에 저장
          for (var window in _currentSessionWindows) {
            await DatabaseHelper.instance.insertTempMeasurement(
              sessionId: sessionId,
              windowIndex: window['window_index'] as int,
              rms: window['rms'] as double,
              freq: window['freq'] as double,
              fatigue: window['fatigue'] as double,
            );
          }
          print('✅ 임시 측정 데이터 저장 완료 (${_currentSessionWindows.length}개)');

          // Baseline 업데이트 (EMA 방식) - 세션당 1회만 수행
          final baselineManager = BaselineManager.instance;
          if (!_baselineUpdatedThisStop &&
              currentMLMode != model_config.MLMode.endToEnd) {
            await baselineManager.updateBaseline(avgRms, avgFreq);
            _baselineUpdatedThisStop = true;
            print('✅ Baseline 업데이트 완료');
          }

          // User Embedding 계산 및 업데이트
          await DatabaseHelper.instance.calculateAndUpdateUserEmbedding();
          print('✅ User Embedding 계산 및 저장 완료');

          // 사용자 상태 업로드 작업 추가
          try {
            final workerManager = await getWorkerManager();
            await workerManager.addUploadStateTask(userId: 'local_user');
            print('✅ 사용자 상태 업로드 작업 추가 완료');
          } catch (e) {
            print('⚠️ 사용자 상태 업로드 작업 추가 실패: $e');
          }

          // 현재 측정 데이터 업로드 작업 추가
          try {
            final userState = await DatabaseHelper.instance.getUserState();
            final userEmbData =
                await DatabaseHelper.instance.getUserEmbedding();

            final workerManager = await getWorkerManager();
            await workerManager.addDatasetUploadTask(
              userId: 'local_user',
              sessionId: sessionId,
              dataset: {
                'user_id': 'local_user',
                'session_id': sessionId,
                'measure_date': DateTime.now().toIso8601String().split('T')[0],
                'rms': avgRms,
                'freq': avgFreq,
                'fatigue': avgFatigue,
                'rms_base': userState?['rms_base'] ?? 0.0,
                'freq_base': userState?['freq_base'] ?? 0.0,
                'user_emb': userEmbData,
                'mode': currentMLMode.name,
                'window_count': _currentSessionWindows.length,
                'created_at': DateTime.now().toIso8601String(),
                'synced': 0,
              },
              priority: 1,
            );
            print('✅ 현재 측정 데이터 업로드 작업 큐에 추가 완료');
          } catch (e) {
            print('⚠️ upload_logs 작업 추가 실패: $e');
          }
        }

        // UI에 결과 전달
        if (_lastWindowResult != null) {
          final sessionAvgResult =
              Map<String, dynamic>.from(_lastWindowResult!);
          sessionAvgResult['fatigueScore'] = avgFatigue;
          sessionAvgResult['fatigueRMS'] = avgRms;
          sessionAvgResult['fatigueVariance'] = _currentSessionWindows
                  .map((w) => w['variance'] as double)
                  .reduce((a, b) => a + b) /
              _currentSessionWindows.length;
          sessionAvgResult['peakFreq'] = avgFreq;
          sessionAvgResult['fatiguePeakFreq'] = avgFreq;
          sessionAvgResult['fatigueLevel'] =
              FatigueCalculator.getFatigueLevel(avgFatigue);
          onAnalysisResult?.call(sessionAvgResult);
        }

        // 측정 횟수 증가
        _measurementCount++;
        print('📊 측정 완료: $_measurementCount회');
      } catch (e, stackTrace) {
        print('❌ 측정 세션 저장 실패: $e');
        print('스택 트레이스: $stackTrace');
      }
    } else {
      print('⚠️ 저장할 측정 데이터가 없습니다');
    }

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    // 다음 세션 대비 플래그 초기화
    _baselineUpdatedThisStop = false;
  }

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
    _currentSamplingRate = 0.0;
    _currentSessionWindows.clear();
    _windowIndex = 0;
    _lastWindowResult = null;
    _windowCount = 0;
  }

  /// 마지막 윈도우 분석 결과 반환
  Map<String, dynamic>? getLastWindowResult() {
    return _lastWindowResult;
  }

  void dispose() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _windowTimer?.cancel();
    clearData();
  }
}
