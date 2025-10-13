import 'dart:math';
import '../models/sensor_data.dart';
import '../models/fatigue_result.dart';
import '../models/user_baseline.dart';
import 'package:uuid/uuid.dart';

/// 센서 데이터 분석 및 피로도 계산 서비스
class AnalysisService {
  final _uuid = const Uuid();

  /// 센서 데이터 리스트로부터 피로도 계산
  Future<FatigueResult> analyzeFatigue({
    required List<SensorData> sensorData,
    required UserBaseline baseline,
    String? userId,
  }) async {
    // 가속도계 데이터 추출
    final accMagnitudes = sensorData.map((data) {
      return sqrt(
        pow(data.accelerometerX, 2) +
            pow(data.accelerometerY, 2) +
            pow(data.accelerometerZ, 2),
      );
    }).toList();

    // RMS (Root Mean Square) 계산
    final rms = _calculateRMS(accMagnitudes);

    // Variance 계산
    final variance = _calculateVariance(accMagnitudes);

    // Dominant Frequency 계산 (간단한 추정)
    final dominantFreq = _estimateDominantFrequency(sensorData);

    // 피로도 지수 계산 (개인화된 baseline 기반)
    final fatigueIndex = _calculateFatigueIndex(
      rms: rms,
      variance: variance,
      dominantFreq: dominantFreq,
      baseline: baseline,
    );

    return FatigueResult(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      fatigueIndex: fatigueIndex.clamp(0.0, 10.0),
      rms: rms,
      variance: variance,
      dominantFrequency: dominantFreq,
      userId: userId,
    );
  }

  /// RMS 계산
  double _calculateRMS(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sumOfSquares = values.fold<double>(0, (sum, val) => sum + val * val);
    return sqrt(sumOfSquares / values.length);
  }

  /// Variance 계산
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumOfSquaredDiff =
        values.fold<double>(0, (sum, val) => sum + pow(val - mean, 2));
    return sumOfSquaredDiff / values.length;
  }

  /// Dominant Frequency 추정 (Zero-Crossing Rate 기반 간단 추정)
  double _estimateDominantFrequency(List<SensorData> data) {
    if (data.length < 2) return 0.0;

    // Zero-crossing 카운트
    int crossings = 0;
    final magnitudes = data.map((d) {
      return sqrt(
        pow(d.accelerometerX, 2) +
            pow(d.accelerometerY, 2) +
            pow(d.accelerometerZ, 2),
      );
    }).toList();

    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;

    for (int i = 0; i < magnitudes.length - 1; i++) {
      if ((magnitudes[i] - mean) * (magnitudes[i + 1] - mean) < 0) {
        crossings++;
      }
    }

    // 샘플링 주파수 가정 (100Hz)
    const samplingRate = 100.0;
    final duration = data.length / samplingRate;
    return crossings / (2 * duration);
  }

  /// 피로도 지수 계산 (개인화된 공식)
  /// Fatigue = α*(RMS/RMS_base) + β*(Freq_base/Freq) + γ*(Var/Var_base)
  double _calculateFatigueIndex({
    required double rms,
    required double variance,
    required double dominantFreq,
    required UserBaseline baseline,
  }) {
    const alpha = 3.0;
    const beta = 3.0;
    const gamma = 4.0;

    final rmsRatio = rms / baseline.rmsBaseline;
    final freqRatio = dominantFreq > 0
        ? baseline.frequencyBaseline / dominantFreq
        : 1.0;
    final varRatio = variance / baseline.varianceBaseline;

    return alpha * rmsRatio + beta * freqRatio + gamma * varRatio;
  }
}

