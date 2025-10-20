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

/// 센서 측정 설정
class SensorConfig {
  // 사용 가능한 프리셋들
  // 각 프리셋은 [측정 1회 = N개 윈도우] 생성
  static const List<MeasurementPreset> presets = [
    MeasurementPreset(
      name: '빠른 측정',
      totalSeconds: 5, // 5초 측정
      windowSeconds: 0.5,
      hopSeconds: 0.25,
      expectedWindows: 19, // → 19개 윈도우 생성
    ),
    MeasurementPreset(
      name: '표준 측정', // 기본값
      totalSeconds: 5, // 5초 측정
      windowSeconds: 0.5,
      hopSeconds: 0.10,
      expectedWindows: 46, // → 46개 윈도우 생성
    ),
    MeasurementPreset(
      name: '정밀 측정',
      totalSeconds: 20,
      windowSeconds: 1.0,
      hopSeconds: 0.5,
      expectedWindows: 39,
    ),
    MeasurementPreset(
      name: '상세 측정',
      totalSeconds: 30,
      windowSeconds: 1.0,
      hopSeconds: 0.5,
      expectedWindows: 59,
    ),
    MeasurementPreset(
      name: '장시간 측정',
      totalSeconds: 60,
      windowSeconds: 2.0,
      hopSeconds: 1.0,
      expectedWindows: 59,
    ),
  ];

  // 현재 선택된 프리셋 (기본값: 표준 측정)
  static MeasurementPreset currentPreset = presets[1];

  // 샘플링 레이트 (Hz)
  static double samplingRate = 50.0;

  // 센서 업데이트 간격 (마이크로초 단위로 계산됨)
  static int get updateIntervalMicroseconds =>
      Duration.microsecondsPerSecond ~/ samplingRate.toInt();

  // 분석 히스토리 최대 개수
  static int maxHistoryCount = 10;

  // 하위 호환성을 위한 getter
  static int get windowSeconds => currentPreset.totalSeconds;

  /// 프리셋 변경
  static void setPreset(MeasurementPreset preset) {
    currentPreset = preset;
    print('⚙️ 측정 프리셋 변경: ${preset.name}');
    print('   - 총 측정 시간: ${preset.totalSeconds}초');
    print('   - 윈도우 크기: ${preset.windowSeconds}초');
    print('   - Hop 크기: ${preset.hopSeconds}초');
    print('   - 예상 윈도우 수: ${preset.expectedWindows}개');
  }

  /// 프리셋 인덱스로 변경
  static void setPresetByIndex(int index) {
    if (index >= 0 && index < presets.length) {
      setPreset(presets[index]);
    }
  }

  // 윈도우 시간 설정 (deprecated)
  @Deprecated('Use setPreset instead')
  static void setWindowSeconds(int seconds) {
    // 호환성 유지
    print('⚠️ setWindowSeconds는 deprecated. setPreset을 사용하세요.');
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
