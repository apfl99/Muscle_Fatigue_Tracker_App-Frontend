import 'dart:math';

/// ---------------------------------------------------------------------------
/// 근피로도 특징 계산 함수
/// 입력: 필터링된 윈도우 간 진동 신호(List<double> data), 샘플링 주파수 fs
/// 출력: RMS, Variance, Peak Frequency (Hz), Mean Power Frequency
/// ---------------------------------------------------------------------------
class FatigueFeatures {
  final double rms;
  final double variance;
  final double peakFrequency;
  final double meanPowerFrequency;
  final double medianFrequency;
  final double stdDev;
  final double zeroCrossing;

  FatigueFeatures({
    required this.rms,
    required this.variance,
    required this.peakFrequency,
    required this.meanPowerFrequency,
    required this.medianFrequency,
    required this.stdDev,
    required this.zeroCrossing,
  });

  Map<String, double> toMap() {
    return {
      'rms': rms,
      'variance': variance,
      'peakFreq': peakFrequency,
      'meanPowerFreq': meanPowerFrequency,
      'medianFreq': medianFrequency,
      'stdDev': stdDev,
      'zeroCrossing': zeroCrossing,
    };
  }
}

/// 근피로도 특징 계산
FatigueFeatures calculateFatigueFeatures(List<double> data, double fs) {
  if (data.isEmpty) {
    print('⚠️ 데이터가 비어있음');
    return FatigueFeatures(
      rms: 0.0,
      variance: 0.0,
      peakFrequency: 0.0,
      meanPowerFrequency: 0.0,
      medianFrequency: 0.0,
      stdDev: 0.0,
      zeroCrossing: 0.0,
    );
  }

  if (fs <= 0) {
    print('⚠️ 샘플링 레이트가 유효하지 않음: $fs Hz, 기본값 50Hz 사용');
    fs = 50.0;
  }

  try {
    final n = data.length;

    // ① RMS 계산
    double sumSquares = 0.0;
    for (final value in data) {
      sumSquares += value * value;
    }
    final rms = sqrt(sumSquares / n);

    // ② 평균 계산
    double sum = 0.0;
    for (final value in data) {
      sum += value;
    }
    final mean = sum / n;

    // ③ 분산 & 표준편차 계산
    double sumSquaredDiff = 0.0;
    for (final value in data) {
      final diff = value - mean;
      sumSquaredDiff += diff * diff;
    }
    final variance = sumSquaredDiff / (n - 1);
    final stdDev = sqrt(variance);

    // ④ Zero Crossing Rate 계산 (주파수 추정에 사용)
    int zeroCrossings = 0;
    for (int i = 1; i < n; i++) {
      if ((data[i] >= 0 && data[i - 1] < 0) ||
          (data[i] < 0 && data[i - 1] >= 0)) {
        zeroCrossings++;
      }
    }
    final zeroCrossingRate = zeroCrossings / (n - 1);

    // ⑤ 간단한 DFT로 주파수 특징 계산 (부분적으로만 계산)
    final maxFreqBin = min(100, n ~/ 2); // 최대 100개 주파수 빈만 계산

    // 안전한 검사 추가
    if (maxFreqBin <= 0) {
      print('⚠️ DFT 계산 불가: maxFreqBin=$maxFreqBin, n=$n');
      return FatigueFeatures(
        rms: rms,
        variance: variance,
        peakFrequency: 0.0,
        meanPowerFrequency: 0.0,
        medianFrequency: 0.0,
        stdDev: stdDev,
        zeroCrossing: zeroCrossingRate * fs / 2,
      );
    }

    final magnitudes = List<double>.filled(maxFreqBin, 0.0);

    for (int k = 0; k < maxFreqBin; k++) {
      double real = 0.0;
      double imag = 0.0;

      for (int i = 0; i < n; i++) {
        final angle = -2 * pi * k * i / n;
        real += data[i] * cos(angle);
        imag += data[i] * sin(angle);
      }

      magnitudes[k] = sqrt(real * real + imag * imag) / n;
    }

    // Peak Frequency 찾기 (DC 성분 제외, 1번 빈부터 시작)
    int peakIndex = 1; // 0번 빈(DC) 제외
    double maxMag = magnitudes.length > 1 ? magnitudes[1] : 0.0;

    // 안전한 검사
    if (magnitudes.length > 1) {
      for (int i = 2; i < magnitudes.length; i++) {
        if (magnitudes[i] > maxMag) {
          maxMag = magnitudes[i];
          peakIndex = i;
        }
      }
    }
    final peakFreq = peakIndex * fs / n;

    // 디버깅 정보 추가
    print('🔍 주파수 분석 디버그:');
    print('   - 샘플 수: $n, 샘플링 레이트: ${fs.toStringAsFixed(1)} Hz');
    print('   - 최대 magnitude: ${maxMag.toStringAsFixed(4)}');
    print('   - Peak index: $peakIndex');
    print('   - Peak frequency: ${peakFreq.toStringAsFixed(2)} Hz');

    // Mean Power Frequency 계산
    double sumFreqPower = 0.0;
    double sumPower = 0.0;
    if (magnitudes.length > 1) {
      for (int i = 1; i < magnitudes.length; i++) {
        final freq = i * fs / n;
        final power = magnitudes[i] * magnitudes[i];
        sumFreqPower += freq * power;
        sumPower += power;
      }
    }
    final meanPowerFreq = sumPower > 0 ? sumFreqPower / sumPower : 0.0;

    // Median Frequency 계산
    double halfPower = sumPower / 2;
    double cumPower = 0.0;
    double medianFreq = 0.0;
    if (magnitudes.length > 1) {
      for (int i = 1; i < magnitudes.length; i++) {
        cumPower += magnitudes[i] * magnitudes[i];
        if (cumPower >= halfPower) {
          medianFreq = i * fs / n;
          break;
        }
      }
    }

    return FatigueFeatures(
      rms: rms,
      variance: variance,
      peakFrequency: peakFreq,
      meanPowerFrequency: meanPowerFreq,
      medianFrequency: medianFreq,
      stdDev: stdDev,
      zeroCrossing: zeroCrossingRate * fs / 2, // Hz로 변환
    );
  } catch (e) {
    print('❌ 근피로도 계산 오류: $e');
    return FatigueFeatures(
      rms: 0.0,
      variance: 0.0,
      peakFrequency: 0.0,
      meanPowerFrequency: 0.0,
      medianFrequency: 0.0,
      stdDev: 0.0,
      zeroCrossing: 0.0,
    );
  }
}

/// 간단한 버전 (주파수 분석 없이)
Map<String, double> calculateBasicFeatures(List<double> data) {
  if (data.isEmpty) {
    return {'rms': 0.0, 'variance': 0.0, 'mean': 0.0, 'stdDev': 0.0};
  }

  try {
    final n = data.length;

    // RMS 계산
    double sumSquares = 0.0;
    for (final value in data) {
      sumSquares += value * value;
    }
    final rms = sqrt(sumSquares / n);

    // 평균 계산
    double sum = 0.0;
    for (final value in data) {
      sum += value;
    }
    final mean = sum / n;

    // 분산 & 표준편차 계산
    double sumSquaredDiff = 0.0;
    for (final value in data) {
      final diff = value - mean;
      sumSquaredDiff += diff * diff;
    }
    final variance = sumSquaredDiff / (n - 1);
    final stdDev = sqrt(variance);

    return {
      'rms': rms,
      'variance': variance,
      'mean': mean,
      'stdDev': stdDev,
    };
  } catch (e) {
    print('❌ 기본 특징 계산 오류: $e');
    return {'rms': 0.0, 'variance': 0.0, 'mean': 0.0, 'stdDev': 0.0};
  }
}
