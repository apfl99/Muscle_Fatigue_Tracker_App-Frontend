/// 센서 측정 설정
class SensorConfig {
  // 윈도우 크기 (초 단위)
  static int windowSeconds = 5;

  // 샘플링 레이트 (Hz)
  static double samplingRate = 50.0;

  // 센서 업데이트 간격 (마이크로초 단위로 계산됨)
  static int get updateIntervalMicroseconds =>
      Duration.microsecondsPerSecond ~/ samplingRate.toInt();

  // 분석 히스토리 최대 개수
  static int maxHistoryCount = 10;

  // 윈도우 시간 설정
  static void setWindowSeconds(int seconds) {
    if (seconds > 0 && seconds <= 60) {
      windowSeconds = seconds;
    } else {
      throw ArgumentError('윈도우 시간은 1초에서 60초 사이여야 합니다.');
    }
  }

  // 샘플링 레이트 설정
  static void setSamplingRate(double rate) {
    if (rate > 0 && rate <= 100) {
      samplingRate = rate;
    } else {
      throw ArgumentError('샘플링 레이트는 0Hz에서 100Hz 사이여야 합니다.');
    }
  }
}
