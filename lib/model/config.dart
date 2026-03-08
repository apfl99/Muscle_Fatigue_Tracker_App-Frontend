/// 데이터베이스 및 계산 관련 상수 모음
library;

/// ========== 데이터베이스 설정 ==========

/// 데이터베이스 파일 이름
class DatabaseConstants {
  static const String fatigueDbName = 'fatigue_results.db';
  static const String baselineDbName = 'baseline.db';

  // 테이블 이름
  static const String fatigueTableName = 'fatigue_results';
  static const String baselineTableName = 'baseline';

  // 쿼리 제한
  static const int defaultQueryLimit = 20;
  static const int baselineHistoryLimit = 10;
}

/// ========== Baseline 관련 설정 ==========
///
/// 주요 개념:
/// - **측정(Measurement)**: 사용자가 버튼 눌러 한 번 측정 (5초, 20초 등)
/// - **윈도우(Window)**: 측정 내부에서 여러 개 생성 (슬라이딩 윈도우)
///   예: 5초 측정 = 19개 윈도우 (W=0.5s, H=0.25s)
/// - **DB 저장**: 윈도우마다 저장 (ML 학습 데이터용)
/// - **Baseline 업데이트**: 측정마다 1번 (마지막 윈도우 평균값 사용)
/// - **사용자 표시**: 측정 단위로 그룹핑 (윈도우 평균)

/// Baseline 자동 보정 설정 (EMA 기반)
class BaselineConstants {
  // EMA (Exponential Moving Average) 학습률
  static const double alphaRms = 0.1; // RMS 학습률 (0.05~0.1, 단기 변화에 둔감)
  static const double alphaFreq = 0.15; // Freq 학습률 (0.1~0.2, 빠른 변화 반영)

  // 초기 캘리브레이션 (측정 횟수 기준)
  static const int calibrationWindows = 1; // 첫 1회만으로 초기화 후 즉시 EMA 시작

  // Outlier 임계값 (표준편차의 N배)
  static const double outlierThreshold = 2.0;

  // 기본 Baseline 값 (일반인 평균값)
  static const double defaultRmsBase = 0.02; // 일반인 평균 RMS
  static const double defaultFreqBase = 1.5; // 일반인 평균 주파수 (Hz)
}

/// ========== 근육 컨디션 계산 설정 ==========

/// 컨디션 계산 가중치
class FatigueConstants {
  // 공식: Fatigue = α·(RMS/RMS_base) + β·(Freq_base/Freq)
  static const double alpha = 0.6; // RMS 가중치 (실제 공식에서는 1.0)
  static const double beta = 0.4; // 주파수 가중치 (실제 공식에서는 1.0)

  // 컨디션 점수 범위 (1.0 기준)
  static const double minFatigue = 1.0; // 최소 1.0으로 클램프
  static const double maxFatigue = 3.0; // 최대값

  // 컨디션 레벨 경계값 (새 기준)
  static const double normalThreshold = 1.1; // 정상
  static const double lightThreshold = 1.4; // 회복 중
  static const double midThreshold = 1.8; // 회복 지연
  // 1.8 이상은 회복 필요

  // 변화량 임계값
  static const double noChangeDelta = 0.1; // 변화 없음
  static const double lightIncreaseDelta = 0.1; // 약간 상승
  static const double heavyIncreaseDelta = 0.3; // 급상승
}

/// 컨디션 색상 정의 (모든 화면에서 통일)
class FatigueColors {
  // 컨디션 레벨별 색상
  static const int normalColor = 0xFF4CAF50; // 초록 (정상)
  static const int lightColor = 0xFFFFA726; // 주황 (회복 중)
  static const int midColor = 0xFFFF7043; // 진한 주황 (회복 지연)
  static const int highColor = 0xFFE53935; // 빨강 (회복 필요)
}

/// ========== ML 단계 전환 설정 ==========
///
/// Phase 전환은 **총 윈도우 수**를 기준으로 함
///
/// 예시) 하루 4회 측정 (각 측정 = 5초, 19개 윈도우):
/// - 1일: 76개 윈도우
/// - 3일: 228개 윈도우 → Phase 2 (Hybrid) 전환
/// - 4일: 304개 윈도우 → Phase 3 (End-to-End) 전환
/// - 14일: 1064개 윈도우

/// ML 도입 전략 (단계별)
/// 새로운 스키마에서는 측정 세션 수 기준으로 변경
class MLPhaseConstants {
  // 단계 전환 임계값 (총 측정 세션 수 기준)
  static const int emaPhaseThreshold = 10; // Phase 1: FMA (최근 10회 측정)
  static const int hybridPhaseThreshold = 20; // Phase 2: Hybrid (다음 10회)
  static const int endToEndPhaseThreshold =
      20; // Phase 3: End-to-End (20회 이상, 추가 확장 시 조정)

  // Hybrid 모드 가중치
  static const double emaWeight = 0.7; // EMA baseline 가중치
  static const double mlWeight = 0.3; // ML 보정 가중치

  // Baseline 변화율 안정성 기준
  static const double baselineStabilityThreshold = 0.01; // 1% 미만
}

/// ML 모드 열거형
enum MLMode {
  ema('기본 학습', '개인 기준값 만들기', 1),
  hybrid('향상 분석', 'AI 보조 분석', 2),
  endToEnd('완전 AI 분석', 'AI 직접 예측', 3);

  final String displayName;
  final String description;
  final int phase;

  const MLMode(this.displayName, this.description, this.phase);
}

/// 게이지 설정
class GaugeConstants {
  // 게이지 스케일 변환 (Fatigue 1.0 → 0%, 2.0 → 100%)
  static const double gaugeMin = 1.0;
  static const double gaugeMax = 2.0;

  static double fatigueToGauge(double fatigue) {
    double value = ((fatigue - gaugeMin) * 100);
    if (value < 0) value = 0;
    if (value > 100) value = 100;
    return value;
  }
}
