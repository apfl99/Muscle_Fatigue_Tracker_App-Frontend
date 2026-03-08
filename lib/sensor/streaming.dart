import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
import '../model/personalization_manager.dart';
import '../utils/user_identity.dart';

class SensorStreaming {
  // Raw 데이터 버퍼
  List<double> accelX = [];
  List<double> accelY = [];
  List<double> accelZ = [];
  List<double> gyroX = [];
  List<double> gyroY = [];
  List<double> gyroZ = [];

  final List<double> _accelBufferX = [];
  final List<double> _accelBufferY = [];
  final List<double> _accelBufferZ = [];
  final List<double> _gyroBufferX = [];
  final List<double> _gyroBufferY = [];
  final List<double> _gyroBufferZ = [];

  // 분석용 버퍼
  final List<double> _windowBuffer = [];
  final List<double> _filteredBuffer = [];

  final MotionFilterAdaptive _filter = MotionFilterAdaptive();

  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;
  Timer? _windowTimer;

  int _measurementCount = 0;
  Function(Map<String, dynamic>)? onAnalysisResult;
  VoidCallback? onAiProcessingStart;
  VoidCallback? onAiProcessingEnd;

  double _currentSamplingRate = 0.0;
  int? _lastSampleTime;

  // 측정 세션 데이터
  final List<Map<String, dynamic>> _currentSessionWindows = [];
  int _windowIndex = 0;
  Map<String, dynamic>? _lastWindowResult;

  // 윈도우 생성 카운터
  int _windowCount = 0;
  List<double>? _cachedUserEmbedding;
  HybridFatigueResponse? _lastHybridResponse;
  HybridFatigueResponse? _prefetchedHybridResponse;
  Future<HybridFatigueResponse?>? _inFlightHybridRequest;
  bool _isHybridPrefetching = false;

  static const int _hybridPrefetchWindowThreshold = 4;

  static const double _lowMotionRmsThreshold = 2.0;
  static const double _lowMotionFreqThreshold = 1.0;

  int? _measurementStartMs;
  double? _prevWindowFatigue;

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
    if (kDebugMode) {
      print('\n🚀 센서 시작 시도');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
    _measurementCount = 0;
    if (kDebugMode) {
      print('📊 측정 횟수 초기화: $_measurementCount회');
    }
    _cachedUserEmbedding = null;

    try {
      if (kDebugMode) {
        print('⚙️ 센서 설정:');
        print('   - 총 측정 시간: ${SensorConfig.totalSeconds}초');
        print('   - 윈도우 크기: ${SensorConfig.windowSeconds}초');
        print('   - Hop 크기: ${SensorConfig.hopSeconds}초');
        print('   - 예상 윈도우 수: ${SensorConfig.expectedWindows}개');
        print('   - 샘플링 레이트(목표): $targetRate Hz');
      }

      _windowBuffer.clear();
      _filteredBuffer.clear();
      _filter.reset();
      _currentSessionWindows.clear();
      _windowIndex = 0;
      _windowCount = 0;
      _measurementStartMs = DateTime.now().millisecondsSinceEpoch;
      _prevWindowFatigue = null;

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
            _accelBufferX.add(event.x);
            _accelBufferY.add(event.y);
            _accelBufferZ.add(event.z);

            // 필터 처리
            final filtered = _filter.process(event.x, event.y, event.z, now);
            _filteredBuffer.add(filtered);

            // Magnitude 계산
            final mag =
                sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
            _windowBuffer.add(mag);

            if (kDebugMode && sensorEventCount <= 10) {
              print(
                  '📥 센서 이벤트 #$sensorEventCount: Raw=(${event.x.toStringAsFixed(2)}, ${event.y.toStringAsFixed(2)}, ${event.z.toStringAsFixed(2)}), '
                  'Filtered=${filtered.toStringAsFixed(4)}');
            }

            // 필터링된 데이터가 모두 0에 가까운지 확인
            if (kDebugMode && sensorEventCount % 50 == 0) {
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
            if (kDebugMode) {
              print('❌ 센서 데이터 처리 오류: $e');
            }
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ 가속도계 에러: $error');
          }
        },
      );

      _gyroSubscription = gyroscopeEventStream()
          .throttleTime(const Duration(milliseconds: 20))
          .listen(
        (event) {
          gyroX.add(event.x);
          gyroY.add(event.y);
          gyroZ.add(event.z);
          _gyroBufferX.add(event.x);
          _gyroBufferY.add(event.y);
          _gyroBufferZ.add(event.z);
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ 자이로스코프 에러: $error');
          }
        },
      );

      _startSlidingWindowAnalysis();
      if (kDebugMode) {
        print('✅ 센서 측정 시작 성공');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ 센서 시작 실패: $e');
        print('스택 트레이스: $st');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      }
      return false;
    }
  }

  // 슬라이딩 윈도우 분석
  void _startSlidingWindowAnalysis() {
    if (kDebugMode) {
      print('📊 슬라이딩 윈도우 분석 시작');
      print(
        '   - 윈도우 크기: ${SensorConfig.windowSeconds}초, Hop 크기: ${SensorConfig.hopSeconds}초',
      );
      print('   - 예상 윈도우 수: ${SensorConfig.expectedWindows}개');
      print('   - 타이머 주기: ${(SensorConfig.hopSeconds * 1000).toInt()}ms');
    }

    _windowTimer = Timer.periodic(
      Duration(milliseconds: (SensorConfig.hopSeconds * 1000).toInt()),
      (timer) {
        final shouldDebug = kDebugMode && timer.tick % 10 == 0;
        if (shouldDebug) {
          print('⏰ 슬라이딩 윈도우 타이머 실행 (${timer.tick}번째)');
        }

        // 실제 샘플링 레이트가 0이면 기본값 사용
        final effectiveSamplingRate =
            _currentSamplingRate > 0 ? _currentSamplingRate : 50.0;
        final windowSamples =
            SensorConfig.getWindowSamples(effectiveSamplingRate);

        if (shouldDebug) {
          print(
            '📊 윈도우 요구사항: $windowSamples개 샘플 (${effectiveSamplingRate.toStringAsFixed(1)} Hz)',
          );
          print('📊 현재 버퍼: ${_filteredBuffer.length}개 샘플');
        }

        // 윈도우 생성 조건 완화: 최소 50% 이상이면 생성
        final minRequiredSamples = (windowSamples * 0.5).round();
        if (_filteredBuffer.length < minRequiredSamples) {
          if (shouldDebug) {
            print(
              '⏳ 대기 중: ${_filteredBuffer.length}/$minRequiredSamples (최소 요구량)',
            );
          }
          return;
        }

        // 실제 사용할 샘플 수 (버퍼 크기에 맞춤)
        final actualSamples = _filteredBuffer.length < windowSamples
            ? _filteredBuffer.length
            : windowSamples;

        if (shouldDebug) {
          print('📊 실제 사용 샘플: $actualSamples개');
        }

        final windowData = _filteredBuffer.sublist(0, actualSamples);
        final hopSamples = SensorConfig.getHopSamples(effectiveSamplingRate);
        final actualHopSamples =
            (hopSamples.clamp(0, _filteredBuffer.length) as num).toInt();
        _filteredBuffer.removeRange(0, actualHopSamples);

        if (shouldDebug) {
          print('📊 Hop 제거: $actualHopSamples개 샘플');
        }

        _windowCount++;
        if (shouldDebug) {
          print(
            '✅ 윈도우 추출 완료 (${windowData.length} samples) - 총 $_windowCount개 윈도우',
          );
        }
        _processSegment(windowData);
        if (_accelBufferX.isNotEmpty) {
          final removeAccel = _minInt([actualHopSamples, _accelBufferX.length]);
          if (removeAccel > 0) {
            _accelBufferX.removeRange(0, removeAccel);
            _accelBufferY.removeRange(
              0,
              _minInt([removeAccel, _accelBufferY.length]),
            );
            _accelBufferZ.removeRange(
              0,
              _minInt([removeAccel, _accelBufferZ.length]),
            );
          }
        }
        if (_gyroBufferX.isNotEmpty) {
          final removeGyro = _minInt([actualHopSamples, _gyroBufferX.length]);
          if (removeGyro > 0) {
            _gyroBufferX.removeRange(0, removeGyro);
            _gyroBufferY.removeRange(
              0,
              _minInt([removeGyro, _gyroBufferY.length]),
            );
            _gyroBufferZ.removeRange(
              0,
              _minInt([removeGyro, _gyroBufferZ.length]),
            );
          }
        }
      },
    );
  }

  // 윈도우 분석
  Future<void> _processSegment(List<double> segmentData) async {
    if (kDebugMode) {
      print('\n🔬 데이터 분석 시작');
    }
    if (segmentData.isEmpty) {
      if (kDebugMode) {
        print('❌ 오류: 분석할 데이터 없음');
      }
      return;
    }

    try {
      final filteredData = segmentData;
      if (kDebugMode) {
        print(
          '✅ 데이터 검증 통과 (${filteredData.length} samples @ ${_currentSamplingRate.toStringAsFixed(1)} Hz)',
        );
      }

      // 필터링된 데이터의 통계 확인
      final mean = _calculateMean(filteredData);
      final rms = _calculateRMS(filteredData);
      final variance = _calculateVariance(filteredData, mean);

      if (kDebugMode) {
        print(
          '📊 필터링된 데이터 통계: RMS=${rms.toStringAsFixed(4)}, VAR=${variance.toStringAsFixed(4)}',
        );
      }

      // 필터링된 데이터가 모두 0에 가까우면 원시 magnitude 사용
      List<double> analysisData = filteredData;
      if (rms < 0.001) {
        if (kDebugMode) {
          print('⚠️ 필터링된 데이터가 너무 작음, 원시 magnitude 사용');
        }
        // 윈도우 크기만큼 원시 magnitude 데이터 추출
        final windowSamples = segmentData.length;
        final startIndex = _windowBuffer.length - windowSamples;

        if (kDebugMode) {
          print('🔍 원시 데이터 추출 디버그:');
          print('   - windowSamples: $windowSamples');
          print('   - _windowBuffer.length: ${_windowBuffer.length}');
          print('   - startIndex: $startIndex');
        }

        if (startIndex >= 0 &&
            startIndex < _windowBuffer.length &&
            windowSamples > 0) {
          try {
            analysisData =
                _windowBuffer.sublist(startIndex, _windowBuffer.length);
            final rawMean = _calculateMean(analysisData);
            final rawRms = _calculateRMS(analysisData);
            if (kDebugMode) {
              print(
                '📊 원시 magnitude 통계: RMS=${rawRms.toStringAsFixed(4)}, VAR=${_calculateVariance(analysisData, rawMean).toStringAsFixed(4)}',
              );
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ 원시 데이터 추출 실패: $e, 필터링된 데이터 사용');
            }
            analysisData = filteredData;
          }
        } else {
          if (kDebugMode) {
            print('❌ 원시 데이터 인덱스 오류, 필터링된 데이터 사용');
          }
          analysisData = filteredData;
        }
      }

      // 샘플링 레이트가 유효하지 않으면 기본값 사용
      final effectiveSamplingRate =
          _currentSamplingRate > 0 ? _currentSamplingRate : 50.0;
      if (kDebugMode) {
        print(
          '📊 주파수 분석용 샘플링 레이트: ${effectiveSamplingRate.toStringAsFixed(1)} Hz',
        );
      }

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
          fatigueScore = FatigueCalculator.calculateFatigue(
            rms: fatigueFeatures.rms,
            peakFreq: fatigueFeatures.peakFrequency,
            rmsBase: rmsBase,
            freqBase: freqBase,
          );
          break;
      }

      final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);
      if (kDebugMode) {
        print(
          '💪 근육 컨디션 계산 완료 → 점수: ${fatigueScore.toStringAsFixed(2)} ($fatigueLevel)',
        );

        // 🔎 분석 결과 상세 로그 (정확도 확인용)
        print('🔎 분석 결과 → '
            'RMS=${fatigueFeatures.rms.toStringAsFixed(4)}, '
            'VAR=${fatigueFeatures.variance.toStringAsFixed(4)}, '
            'FREQ=${fatigueFeatures.peakFrequency.toStringAsFixed(2)} Hz');
      }

      // 윈도우 결과를 세션에 저장
      final windowSizeMs = (SensorConfig.windowSeconds * 1000).toInt();
      final hopMs = (SensorConfig.hopSeconds * 1000).toInt();
      final baseStart =
          _measurementStartMs ?? DateTime.now().millisecondsSinceEpoch;
      final windowStartMs = baseStart + (_windowIndex * hopMs);
      final windowEndMs = windowStartMs + windowSizeMs;
      final timestampUtc = DateTime.now().toUtc().toIso8601String();
      final fatiguePrev = _prevWindowFatigue;
      final fatigueLevelInt = _fatigueLevelToInt(fatigueScore);
      final overlapRate = windowSizeMs > 0 ? 1.0 - (hopMs / windowSizeMs) : 0.5;

      double gyroRms = 0.0;
      double gyroMeanFreq = 0.0;

      final windowData = {
        'window_id': _windowIndex,
        'window_index': _windowIndex,
        'rms': fatigueFeatures.rms,
        'freq': fatigueFeatures.peakFrequency,
        'fatigue': fatigueScore,
        'variance': fatigueFeatures.variance,
        'mean_power_freq': fatigueFeatures.meanPowerFrequency,
        'median_freq': fatigueFeatures.medianFrequency,
        'sample_count': analysisData.length,
        'timestamp': DateTime.now().toIso8601String(),
        'timestamp_utc': timestampUtc,
        'window_start_ms': windowStartMs,
        'window_end_ms': windowEndMs,
        'rms_acc': fatigueFeatures.rms,
        'mean_freq_acc': fatigueFeatures.meanPowerFrequency,
        'stability_index': fatigueFeatures.variance,
        'fatigue_prev': fatiguePrev ?? 0.0,
        'fatigue_level': fatigueLevelInt,
        'window_size_ms': windowSizeMs,
        'overlap_rate': overlapRate,
        'rms_base': rmsBase,
        'freq_base': freqBase,
        'quality_flag': 1,
      };

      final accelSampleCount = _minInt([
        analysisData.length,
        _accelBufferX.length,
        _accelBufferY.length,
        _accelBufferZ.length,
      ]);
      if (accelSampleCount > 0) {
        final accelWindowX =
            List<double>.from(_accelBufferX.sublist(0, accelSampleCount));
        final accelWindowY =
            List<double>.from(_accelBufferY.sublist(0, accelSampleCount));
        final accelWindowZ =
            List<double>.from(_accelBufferZ.sublist(0, accelSampleCount));

        final accMeanX = _calculateMean(accelWindowX);
        final accMeanY = _calculateMean(accelWindowY);
        final accMeanZ = _calculateMean(accelWindowZ);

        windowData
          ..['acc_x_mean'] = accMeanX
          ..['acc_y_mean'] = accMeanY
          ..['acc_z_mean'] = accMeanZ
          ..['acc_x_std'] = sqrt(_calculateVariance(accelWindowX, accMeanX))
          ..['acc_y_std'] = sqrt(_calculateVariance(accelWindowY, accMeanY))
          ..['acc_z_std'] = sqrt(_calculateVariance(accelWindowZ, accMeanZ))
          ..['gravity_x_mean'] = accMeanX
          ..['gravity_y_mean'] = accMeanY
          ..['gravity_z_mean'] = accMeanZ
          ..['linacc_x_mean'] =
              _calculateMeanAbsoluteDeviation(accelWindowX, accMeanX)
          ..['linacc_y_mean'] =
              _calculateMeanAbsoluteDeviation(accelWindowY, accMeanY)
          ..['linacc_z_mean'] =
              _calculateMeanAbsoluteDeviation(accelWindowZ, accMeanZ);

        final accelMagnitude = List<double>.generate(
          accelSampleCount,
          (i) => sqrt(
            accelWindowX[i] * accelWindowX[i] +
                accelWindowY[i] * accelWindowY[i] +
                accelWindowZ[i] * accelWindowZ[i],
          ),
        );
        final jerkValues = <double>[];
        for (int i = 1; i < accelMagnitude.length; i++) {
          final diff = (accelMagnitude[i] - accelMagnitude[i - 1]) *
              effectiveSamplingRate;
          jerkValues.add(diff);
        }
        if (jerkValues.isNotEmpty) {
          final jerkMean = _calculateMean(jerkValues);
          windowData['jerk_mean'] = jerkMean;
          windowData['jerk_std'] =
              sqrt(_calculateVariance(jerkValues, jerkMean));
        } else {
          windowData['jerk_mean'] = 0.0;
          windowData['jerk_std'] = 0.0;
        }
        windowData['entropy_acc'] = _calculateSpectralEntropy(accelMagnitude);
      } else {
        windowData
          ..['acc_x_mean'] = 0.0
          ..['acc_y_mean'] = 0.0
          ..['acc_z_mean'] = 0.0
          ..['acc_x_std'] = 0.0
          ..['acc_y_std'] = 0.0
          ..['acc_z_std'] = 0.0
          ..['gravity_x_mean'] = 0.0
          ..['gravity_y_mean'] = 0.0
          ..['gravity_z_mean'] = 0.0
          ..['linacc_x_mean'] = 0.0
          ..['linacc_y_mean'] = 0.0
          ..['linacc_z_mean'] = 0.0
          ..['entropy_acc'] = 0.0
          ..['jerk_mean'] = 0.0
          ..['jerk_std'] = 0.0;
      }

      final gyroSampleCount = _minInt([
        analysisData.length,
        _gyroBufferX.length,
        _gyroBufferY.length,
        _gyroBufferZ.length,
      ]);
      if (gyroSampleCount > 0) {
        final gyroWindowX =
            List<double>.from(_gyroBufferX.sublist(0, gyroSampleCount));
        final gyroWindowY =
            List<double>.from(_gyroBufferY.sublist(0, gyroSampleCount));
        final gyroWindowZ =
            List<double>.from(_gyroBufferZ.sublist(0, gyroSampleCount));

        final gyroMeanX = _calculateMean(gyroWindowX);
        final gyroMeanY = _calculateMean(gyroWindowY);
        final gyroMeanZ = _calculateMean(gyroWindowZ);

        windowData
          ..['gyro_x_mean'] = gyroMeanX
          ..['gyro_y_mean'] = gyroMeanY
          ..['gyro_z_mean'] = gyroMeanZ
          ..['gyro_x_std'] = sqrt(_calculateVariance(gyroWindowX, gyroMeanX))
          ..['gyro_y_std'] = sqrt(_calculateVariance(gyroWindowY, gyroMeanY))
          ..['gyro_z_std'] = sqrt(_calculateVariance(gyroWindowZ, gyroMeanZ));

        final gyroMagnitude = List<double>.generate(
          gyroSampleCount,
          (i) => sqrt(
            gyroWindowX[i] * gyroWindowX[i] +
                gyroWindowY[i] * gyroWindowY[i] +
                gyroWindowZ[i] * gyroWindowZ[i],
          ),
        );
        gyroRms = _calculateVectorRMS(gyroWindowX, gyroWindowY, gyroWindowZ);
        gyroMeanFreq =
            _calculateMeanFrequency(gyroMagnitude, effectiveSamplingRate);
        windowData['rms_gyro'] = gyroRms;
        windowData['mean_freq_gyro'] = gyroMeanFreq;
        windowData['entropy_gyro'] = _calculateSpectralEntropy(gyroMagnitude);
      } else {
        windowData
          ..['gyro_x_mean'] = 0.0
          ..['gyro_y_mean'] = 0.0
          ..['gyro_z_mean'] = 0.0
          ..['gyro_x_std'] = 0.0
          ..['gyro_y_std'] = 0.0
          ..['gyro_z_std'] = 0.0
          ..['rms_gyro'] = 0.0
          ..['mean_freq_gyro'] = 0.0
          ..['entropy_gyro'] = 0.0;
        gyroRms = 0.0;
        gyroMeanFreq = 0.0;
      }
      final expectedSamples =
          (SensorConfig.windowSeconds * effectiveSamplingRate).round();
      final normalizedExpected = expectedSamples <= 0 ? 1 : expectedSamples;
      final coverage =
          analysisData.isEmpty ? 0.0 : analysisData.length / normalizedExpected;
      final minSampleThreshold = (normalizedExpected * 0.6).ceil();
      final hasEnoughAccel = accelSampleCount >= minSampleThreshold;
      final hasEnoughGyro = gyroSampleCount >= minSampleThreshold;
      final hasFiniteValues = _hasFiniteMetrics(windowData);

      final isHighQuality =
          coverage >= 0.6 && hasEnoughAccel && hasEnoughGyro && hasFiniteValues;
      windowData['quality_flag'] = isHighQuality ? 1 : 0;

      if (!isHighQuality) {
        print(
          '⚠️ 품질 미달 윈도우 → 제외 (coverage=${coverage.toStringAsFixed(2)}, '
          'accel=$accelSampleCount, gyro=$gyroSampleCount)',
        );
        // "측정이 안 되는 것처럼 보이는" 케이스 방지:
        // 윈도우가 모두 품질 미달이면 세션이 비어서 결과가 null이 되므로,
        // UI에 최소한의 참고 지표(EMA 기반) + 경고를 전달할 수 있도록 lastWindowResult는 갱신한다.
        _lastWindowResult = {
          'fatigueScore': fatigueScore,
          'fatigueLevel': FatigueCalculator.getFatigueLevel(fatigueScore),
          'rms': fatigueFeatures.rms,
          'peakFreq': fatigueFeatures.peakFrequency,
          'fatigueRMS': fatigueFeatures.rms,
          'fatigueVariance': fatigueFeatures.variance,
          'timestamp': DateTime.now(),
          'qualityWarning': true,
          'coverage': coverage,
          'accel': accelSampleCount,
          'gyro': gyroSampleCount,
          'mlMode': mode.name,
        };
        _windowIndex++;
        return;
      }

      final isLowMotion = fatigueFeatures.rms < _lowMotionRmsThreshold &&
          fatigueFeatures.peakFrequency < _lowMotionFreqThreshold;
      windowData['low_motion_flag'] = isLowMotion ? 1 : 0;

      final userEmbedding = await _getUserEmbedding();
      windowData['user_emb'] = List<double>.from(userEmbedding);
      if (mode == model_config.MLMode.endToEnd && !isLowMotion) {
        final e2eScore = await calculateEndToEndFatigue(
          window: windowData,
          rms: fatigueFeatures.rms,
          freq: fatigueFeatures.peakFrequency,
          rmsBase: rmsBase,
          freqBase: freqBase,
        );
        if (e2eScore != null) {
          fatigueScore = e2eScore;
        } else {
          print('⚠️ E2E 추론 실패 → EMA fallback 유지');
        }
      } else if (mode == model_config.MLMode.endToEnd && isLowMotion) {
        print(
          'ℹ️ 저활동 구간 감지 → EMA 결과 사용 (rms=${fatigueFeatures.rms.toStringAsFixed(3)}, '
          'freq=${fatigueFeatures.peakFrequency.toStringAsFixed(3)})',
        );
      }

      double finalFatigueScore = fatigueScore;
      final personalizationManager = PersonalizationManager.instance;
      if (personalizationManager.isPersonalizationActive) {
        final features = {
          'rms_acc': fatigueFeatures.rms,
          'mean_freq_acc': fatigueFeatures.meanPowerFrequency,
          'rms_gyro': gyroRms,
          'mean_freq_gyro': gyroMeanFreq,
          'fatigue': fatigueScore,
        };
        finalFatigueScore = personalizationManager.applyPersonalization(
          features: features,
          fallback: fatigueScore,
        );
      }
      final finalFatigueLevel =
          FatigueCalculator.getFatigueLevel(finalFatigueScore);
      final finalFatigueLevelInt = _fatigueLevelToInt(finalFatigueScore);
      windowData['fatigue_level'] = finalFatigueLevelInt;
      windowData['fatigue_personal'] = finalFatigueScore;
      windowData['fatigue'] = finalFatigueScore;

      _currentSessionWindows.add(windowData);
      _windowIndex++;
      _prevWindowFatigue = finalFatigueScore;
      if (mode == model_config.MLMode.hybrid) {
        _maybeStartHybridPrefetch();
      }

      // 마지막 윈도우 결과 저장
      _lastWindowResult = {
        'fatigueScore': finalFatigueScore,
        'fatigueLevel': finalFatigueLevel,
        'rms': fatigueFeatures.rms,
        'peakFreq': fatigueFeatures.peakFrequency,
        'fatigueRMS': fatigueFeatures.rms,
        'fatigueVariance': fatigueFeatures.variance,
        'timestamp': DateTime.now(),
      };
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ 분석 중 오류: $e');
        print(st);
      }
    }
  }

  int _minInt(List<int> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a < b ? a : b);

  double _calculateMean(List<double> d) =>
      d.isEmpty ? 0.0 : d.reduce((a, b) => a + b) / d.length;
  double _calculateRMS(List<double> d) =>
      d.isEmpty ? 0.0 : sqrt(d.fold(0.0, (s, v) => s + v * v) / d.length);
  double _calculateVariance(List<double> d, double m) =>
      d.isEmpty ? 0.0 : d.fold(0.0, (s, v) => s + pow(v - m, 2)) / d.length;
  double _calculateMeanAbsoluteDeviation(List<double> d, double mean) =>
      d.isEmpty ? 0.0 : d.fold(0.0, (s, v) => s + (v - mean).abs()) / d.length;
  double _calculateVectorRMS(
    List<double> x,
    List<double> y,
    List<double> z,
  ) {
    final length = min(x.length, min(y.length, z.length));
    if (length == 0) return 0.0;
    double sumSquares = 0.0;
    for (int i = 0; i < length; i++) {
      sumSquares += x[i] * x[i] + y[i] * y[i] + z[i] * z[i];
    }
    return sqrt(sumSquares / length);
  }

  double _calculateSpectralEntropy(List<double> values) {
    final n = values.length;
    if (n <= 1) return 0.0;
    final absValues = values.map((v) => v.abs()).toList();
    final total = absValues.fold(0.0, (a, b) => a + b);
    if (total <= 0.0) return 0.0;
    double entropy = 0.0;
    for (final v in absValues) {
      final p = v / total;
      if (p > 0) {
        entropy -= p * (log(p) / log(2));
      }
    }
    final maxEntropy = log(n) / log(2);
    return maxEntropy > 0 ? entropy / maxEntropy : entropy;
  }

  double _calculateMeanFrequency(List<double> values, double fs) {
    final n = values.length;
    if (n <= 1 || fs <= 0) return 0.0;
    final maxFreqBin = min(100, n ~/ 2);
    if (maxFreqBin < 1) return 0.0;
    double sumFreqPower = 0.0;
    double sumPower = 0.0;
    for (int k = 1; k <= maxFreqBin; k++) {
      double real = 0.0;
      double imag = 0.0;
      for (int i = 0; i < n; i++) {
        final angle = -2 * pi * k * i / n;
        real += values[i] * cos(angle);
        imag += values[i] * sin(angle);
      }
      final magnitude = sqrt(real * real + imag * imag);
      final power = magnitude * magnitude;
      final freq = k * fs / n;
      sumFreqPower += freq * power;
      sumPower += power;
    }
    return sumPower > 0 ? sumFreqPower / sumPower : 0.0;
  }

  int _fatigueLevelToInt(double fatigue) {
    if (fatigue < 1.1) return 0;
    if (fatigue < 1.4) return 1;
    return 2;
  }

  // 센서 중지
  Future<void> stopSensor() async {
    if (kDebugMode) {
      print('\n🛑 센서 측정 중지');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }

    try {
      await _accelSubscription?.cancel();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ 가속도계 구독 해제 오류: $e');
      }
    }
    try {
      await _gyroSubscription?.cancel();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ 자이로스코프 구독 해제 오류: $e');
      }
    }
    _windowTimer?.cancel();

    if (kDebugMode) {
      print('📊 최종 통계:');
      print('   - 총 수집된 샘플: ${accelX.length}개');
      print('   - 윈도우 버퍼: ${_windowBuffer.length}개');
      print('   - 필터링된 버퍼: ${_filteredBuffer.length}개');
      print('   - 최종 샘플링 레이트: ${_currentSamplingRate.toStringAsFixed(1)} Hz');
    }

    // 측정 완료: 세션 데이터를 DB에 저장
    if (_currentSessionWindows.isNotEmpty) {
      if (kDebugMode) {
        print('🎯 측정 세션 저장 시작...');
        print('   - 총 윈도우 수: ${_currentSessionWindows.length}개');
      }

      try {
        if (_excludeFromLogging) {
          if (kDebugMode) {
            print('⛔️ 이번 세션은 로그/업로드에서 제외됩니다 (baseline 측정 등)');
          }
          // 제외 플래그는 1회성으로 사용
          _excludeFromLogging = false;
          return;
        }

        final baselineManager = BaselineManager.instance;
        final currentMLMode = baselineManager.getCurrentMLMode();
        if (currentMLMode == model_config.MLMode.hybrid) {
          _maybeStartHybridPrefetch();
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

        double avgFatigue = _currentSessionWindows
                .map(
                  (w) => (w['fatigue_personal'] ?? w['fatigue']) as double,
                )
                .reduce((a, b) => a + b) /
            _currentSessionWindows.length;

        HybridFatigueResponse? aiResponse = _prefetchedHybridResponse;
        if (currentMLMode == model_config.MLMode.hybrid) {
          if (aiResponse == null && _inFlightHybridRequest != null) {
            onAiProcessingStart?.call();
            try {
              aiResponse = await _inFlightHybridRequest;
              _prefetchedHybridResponse = aiResponse;
            } catch (e, stackTrace) {
              if (kDebugMode) {
                print('⚠️ Hybrid 프리페치 대기 중 오류: $e');
                print(stackTrace);
              }
            } finally {
              onAiProcessingEnd?.call();
              _inFlightHybridRequest = null;
            }
          }

          if (aiResponse == null) {
            onAiProcessingStart?.call();
            try {
              aiResponse = await _performHybridRequest();
              _prefetchedHybridResponse = aiResponse;
            } catch (e, stackTrace) {
              if (kDebugMode) {
                print('⚠️ Hybrid 원격 추론 실패: $e');
                print(stackTrace);
              }
            } finally {
              onAiProcessingEnd?.call();
            }
          }
        }

        if (aiResponse != null) {
          avgFatigue = aiResponse.fatigue;
          final aiLevel = _fatigueLevelToInt(avgFatigue);
          for (final window in _currentSessionWindows) {
            window['fatigue'] = avgFatigue;
            window['fatigue_personal'] = avgFatigue;
            window['fatigue_level'] = aiLevel;
            if (aiResponse.modelVersion != null) {
              window['ai_model_version'] = aiResponse.modelVersion;
            }
            window['ai_latency_ms'] = aiResponse.latencyMs;
          }
          _lastHybridResponse = aiResponse;
          _lastWindowResult?['fatigueScore'] = avgFatigue;
          try {
            await DatabaseHelper.instance.updateModelVersion(
              modelType: 'Hybrid',
              version: aiResponse.modelVersion ?? 'server',
              path: 'remote',
            );
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ 모델 버전 업데이트 실패: $e');
            }
          }
        } else {
          _lastHybridResponse = null;
        }

        // 첫 측정/기준값 상태 확인
        final isFirstMeasurement =
            await DatabaseHelper.instance.isFirstMeasurement();
        final hasBaseline = await DatabaseHelper.instance.hasBaseline();

        if (isFirstMeasurement && !hasBaseline) {
          // 기준값 미설정 상태의 첫 측정은 기록/업로드 제외 (baseline 전용)
          if (kDebugMode) {
            print('📊 첫 측정 + 기준값 미설정 → 기록/업로드 제외 (baseline 전용)');
            print('   - 평균 RMS: ${avgRms.toStringAsFixed(4)}');
            print('   - 평균 Freq: ${avgFreq.toStringAsFixed(2)} Hz');
          }
        } else {
          // 일반 측정은 기존대로 저장
          // 현재 ML 모드 가져오기
          // 세션 ID 생성 (timestamp 기반)
          final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';

          final userId = await UserIdentity.instance.userId;

          // 윈도우 단위 데이터 저장
          await DatabaseHelper.instance.insertFatigueWindows(
            userId: userId,
            sessionId: sessionId,
            windows: _currentSessionWindows
                .map((w) => Map<String, dynamic>.from(w))
                .toList(),
            mode: currentMLMode.name,
          );
          if (kDebugMode) {
            print('✅ 컨디션 윈도우 저장 완료 (ID: $sessionId)');
            print('   - 평균 컨디션: ${avgFatigue.toStringAsFixed(2)}');
            print('   - 평균 RMS: ${avgRms.toStringAsFixed(4)}');
            print('   - 평균 Freq: ${avgFreq.toStringAsFixed(2)} Hz');
          }

          // Baseline 업데이트 (EMA 방식) - 세션당 1회만 수행
          if (!_baselineUpdatedThisStop &&
              currentMLMode != model_config.MLMode.endToEnd) {
            await baselineManager.updateBaseline(avgRms, avgFreq);
            _baselineUpdatedThisStop = true;
            if (kDebugMode) {
              print('✅ Baseline 업데이트 완료');
            }
          }

          // User Embedding 계산 및 업데이트
          await DatabaseHelper.instance.calculateAndUpdateUserEmbedding();
          if (kDebugMode) {
            print('✅ User Embedding 계산 및 저장 완료');
          }

          // 현재 측정 데이터 업로드 작업 추가
          try {
            final userState = await DatabaseHelper.instance.getUserState();
            final userEmbData =
                await DatabaseHelper.instance.getUserEmbedding();

            final workerManager = await getWorkerManager();
            await workerManager.addDatasetUploadTask(
              userId: userId,
              sessionId: sessionId,
              dataset: {
                'user_id': userId,
                'session_id': sessionId,
                'mode': currentMLMode.name,
                'avg_rms': avgRms,
                'avg_freq': avgFreq,
                'avg_fatigue': avgFatigue,
                'rms_base': userState?['rms_base'] ?? 0.0,
                'freq_base': userState?['freq_base'] ?? 0.0,
                'user_emb': userEmbData,
                'window_count': _currentSessionWindows.length,
                'windows': _currentSessionWindows
                    .map((w) => Map<String, dynamic>.from(w))
                    .toList(),
                'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
              },
              priority: 1,
            );
            if (kDebugMode) {
              print('✅ 현재 측정 데이터 업로드 작업 큐에 추가 완료');
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ upload_logs 작업 추가 실패: $e');
            }
          }

          await PersonalizationManager.instance.ensurePersonalization();
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
          sessionAvgResult['mlMode'] = currentMLMode.name;
          final hybridResponse = _lastHybridResponse;
          if (hybridResponse != null) {
            sessionAvgResult['aiModelVersion'] = hybridResponse.modelVersion;
            sessionAvgResult['aiLatencyMs'] = hybridResponse.latencyMs;
          }
          onAnalysisResult?.call(sessionAvgResult);
        }

        // 측정 횟수 증가
        _measurementCount++;
        if (kDebugMode) {
          print('📊 측정 완료: $_measurementCount회');
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print('❌ 측정 세션 저장 실패: $e');
          print('스택 트레이스: $stackTrace');
        }
      }
    } else {
      if (kDebugMode) {
        print('⚠️ 저장할 측정 데이터가 없습니다');
      }
      // 모든 윈도우가 품질 미달로 제외된 경우라도, 마지막 윈도우 기반의 참고 지표가 있으면 표시
      final last = _lastWindowResult;
      if (last != null) {
        final result = Map<String, dynamic>.from(last);
        result['qualityWarning'] = true;
        result['mlMode'] ??= BaselineManager.instance.getCurrentMLMode().name;
        onAnalysisResult?.call(result);
      } else {
        onAnalysisResult?.call({
          'fatigueScore': null,
          'qualityWarning': true,
          'mlMode': BaselineManager.instance.getCurrentMLMode().name,
        });
      }
    }

    if (kDebugMode) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    }
    // 다음 세션 대비 플래그 초기화
    _baselineUpdatedThisStop = false;
    _cachedUserEmbedding = null;
    _lastHybridResponse = null;
    _prefetchedHybridResponse = null;
    _inFlightHybridRequest = null;
    _isHybridPrefetching = false;
  }

  void _maybeStartHybridPrefetch() {
    if (_isHybridPrefetching) return;
    if (_prefetchedHybridResponse != null) return;
    if (_currentSessionWindows.length < _hybridPrefetchWindowThreshold) return;
    _isHybridPrefetching = true;
    _inFlightHybridRequest = _performHybridRequest();
    _inFlightHybridRequest?.then((response) {
      if (response != null) {
        _prefetchedHybridResponse = response;
      }
    }).catchError((e, stackTrace) {
      if (kDebugMode) {
        print('⚠️ Hybrid 프리페치 실패: $e');
        if (stackTrace != null) {
          print(stackTrace);
        }
      }
    }).whenComplete(() {
      _isHybridPrefetching = false;
      _inFlightHybridRequest = null;
    });
  }

  Future<HybridFatigueResponse?> _performHybridRequest() async {
    final payload = await _buildHybridPayloadFromSession();
    if (payload == null) return null;
    return MLManager.instance.requestHybridFatigue(
      payload: payload,
      mode: model_config.MLMode.hybrid,
    );
  }

  Future<HybridFatiguePayload?> _buildHybridPayloadFromSession() async {
    if (_currentSessionWindows.isEmpty) return null;
    final baselineManager = BaselineManager.instance;
    final userEmb = await _getUserEmbedding();
    return HybridFatiguePayload(
      rmsAcc: _averageSessionMetric('rms'),
      meanFreqAcc: _averageSessionMetric('mean_freq_acc'),
      rmsGyro: _averageSessionMetric('rms_gyro'),
      meanFreqGyro: _averageSessionMetric('mean_freq_gyro'),
      rmsBase: baselineManager.rmsBase,
      freqBase: baselineManager.freqBase,
      userEmbedding: userEmb,
    );
  }

  double _averageSessionMetric(String key) {
    if (_currentSessionWindows.isEmpty) return 0.0;
    double sum = 0.0;
    int count = 0;
    for (final window in _currentSessionWindows) {
      final value = window[key];
      if (value is num) {
        final doubleValue = value.toDouble();
        if (doubleValue.isFinite) {
          sum += doubleValue;
          count++;
        }
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  Future<List<double>> _getUserEmbedding() async {
    if (_cachedUserEmbedding != null) {
      return _cachedUserEmbedding!;
    }
    try {
      final embedding = await DatabaseHelper.instance.getUserEmbedding();
      _cachedUserEmbedding = List<double>.from(embedding);
    } catch (_) {
      _cachedUserEmbedding = <double>[];
    }
    return _cachedUserEmbedding!;
  }

  bool _hasFiniteMetrics(Map<String, dynamic> window) {
    for (final entry in window.entries) {
      final value = entry.value;
      if (value is double && (!value.isFinite || value.isNaN)) {
        print('⚠️ 비정상 피처 감지 → ${entry.key}=$value');
        return false;
      }
    }
    return true;
  }

  void clearData() {
    accelX.clear();
    accelY.clear();
    accelZ.clear();
    gyroX.clear();
    gyroY.clear();
    gyroZ.clear();
    _accelBufferX.clear();
    _accelBufferY.clear();
    _accelBufferZ.clear();
    _gyroBufferX.clear();
    _gyroBufferY.clear();
    _gyroBufferZ.clear();
    _windowBuffer.clear();
    _filteredBuffer.clear();
    _filter.reset();
    _currentSamplingRate = 0.0;
    _currentSessionWindows.clear();
    _windowIndex = 0;
    _lastWindowResult = null;
    _windowCount = 0;
    _measurementStartMs = null;
    _prevWindowFatigue = null;
    _cachedUserEmbedding = null;
    _lastHybridResponse = null;
    _prefetchedHybridResponse = null;
    _inFlightHybridRequest = null;
    _isHybridPrefetching = false;
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
