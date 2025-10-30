/// 측정 프리셋
///
/// **슬라이딩 윈도우 개념:**
/// - totalSeconds: 사용자가 측정하는 총 시간 (예: 5초)
/// - windowSeconds: 한 번에 분석하는 데이터 구간 (예: 0.5초)
/// - hopSeconds: 윈도우가 이동하는 간격 (예: 0.25초)
/// - expectedWindows: 측정 1회당 생성되는 윈도우 수 (예: 19개)
///
/// **예시: 빠른 측정 (5초, W=0.5s, H=0.25s)**
/// - 사용자: 버튼 1번 클릭 → 5초 측정
/// - 내부 처리: 19개 윈도우 생성 및 DB 저장
/// - 사용자 표시: 19개 윈도우 평균값으로 1개 측정 기록 표시
class MeasurementPreset {
  final String name;
  final int totalSeconds; // 총 측정 시간 (사용자가 측정하는 시간)
  final double windowSeconds; // 윈도우 크기 (분석 단위)
  final double hopSeconds; // hop(stride) 크기 (윈도우 이동 간격)
  final int expectedWindows; // 예상 윈도우 수 (측정당 생성되는 윈도우 수)

  const MeasurementPreset({
    required this.name,
    required this.totalSeconds,
    required this.windowSeconds,
    required this.hopSeconds,
    required this.expectedWindows,
  });

  /// 윈도우 샘플 수 계산 (샘플링 레이트 기준)
  int getWindowSamples(double samplingRate) {
    return (windowSeconds * samplingRate).round();
  }

  /// Hop 샘플 수 계산
  int getHopSamples(double samplingRate) {
    return (hopSeconds * samplingRate).round();
  }

  @override
  String toString() =>
      '$name ($totalSeconds초, W:${windowSeconds}s, H:${hopSeconds}s, ~$expectedWindows개)';
}

/// 센서 측정 설정 (정확도 중심 최적화)
class SensorConfig {
  static const double samplingRate = 50.0; // 센서 목표 주파수 (Hz)
  static const double totalSeconds = 5.0; // 전체 측정 시간
  static const double windowSeconds = 2.0; // 윈도우 길이 (2초로 단축)
  static const double hopSeconds = 0.5; // 슬라이딩 간격 (0.5초로 단축)
  static const int updateIntervalMicroseconds = 20000; // 20ms → 50Hz

  // 분석 히스토리 최대 개수
  static int maxHistoryCount = 10;

  // 하위 호환성을 위한 getter들
  static int get windowSecondsInt => windowSeconds.toInt();
  static int get totalSecondsInt => totalSeconds.toInt();

  // 윈도우 샘플 수 계산 (샘플링 레이트 기준)
  static int getWindowSamples(double actualSamplingRate) {
    return (windowSeconds * actualSamplingRate).round();
  }

  // Hop 샘플 수 계산
  static int getHopSamples(double actualSamplingRate) {
    return (hopSeconds * actualSamplingRate).round();
  }

  // 예상 윈도우 수 계산
  static int get expectedWindows {
    return ((totalSeconds - windowSeconds) / hopSeconds + 1).round();
  }

  @override
  String toString() =>
      'SensorConfig(${totalSeconds}s, W:${windowSeconds}s, H:${hopSeconds}s, ~$expectedWindows개)';
}
