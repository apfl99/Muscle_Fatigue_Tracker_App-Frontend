import 'package:flutter/material.dart';

/// 측정 세션 모델 (measure_sessions 테이블)
class MeasureSession {
  final int? id;
  final DateTime timestamp;
  final double rms;
  final double freq;
  final double fatigue;
  final String mode; // 'ema', 'hybrid', 'end_to_end'
  final int windowCount; // 이 세션에서 생성된 윈도우 수
  final String? signalPath; // 신호 데이터 파일 경로 (optional)
  final int synced; // 서버 동기화 여부 (0=미동기화, 1=동기화됨)

  MeasureSession({
    this.id,
    required this.timestamp,
    required this.rms,
    required this.freq,
    required this.fatigue,
    required this.mode,
    this.windowCount = 0,
    this.signalPath,
    this.synced = 0,
  });

  /// DB에서 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'rms': rms,
      'freq': freq,
      'fatigue': fatigue,
      'mode': mode,
      'window_count': windowCount,
      'signal_path': signalPath,
      'synced': synced,
    };
  }

  /// Map에서 생성
  factory MeasureSession.fromMap(Map<String, dynamic> map) {
    return MeasureSession(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      rms: map['rms'] as double,
      freq: map['freq'] as double,
      fatigue: map['fatigue'] as double,
      mode: map['mode'] as String,
      windowCount: map['window_count'] as int? ?? 0,
      signalPath: map['signal_path'] as String?,
      synced: map['synced'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'MeasureSession{id: $id, timestamp: $timestamp, fatigue: $fatigue, mode: $mode, windowCount: $windowCount}';
  }
}

/// 피로도 계산 헬퍼 클래스
class FatigueCalculator {
  /// 근피로도 점수 계산
  /// Fatigue = α·(RMS/RMS_base) + β·(Freq_base/Freq)
  static double calculateFatigue({
    required double rms,
    required double peakFreq,
    required double rmsBase,
    required double freqBase,
    double alpha = 0.6,
    double beta = 0.4,
  }) {
    // 0으로 나누기 방지
    if (rmsBase <= 0 || peakFreq <= 0 || rms.isNaN || peakFreq.isNaN) {
      print('⚠️ 피로도 계산 불가: rmsBase=$rmsBase, peakFreq=$peakFreq');
      return 1.0;
    }

    final fatigue = alpha * (rms / rmsBase) + beta * (freqBase / peakFreq);

    // NaN 체크
    if (fatigue.isNaN || fatigue.isInfinite) {
      print('⚠️ 피로도 계산 결과 무효: $fatigue');
      return 1.0;
    }

    // 최소 1.0, 최대 3.0으로 클램프
    final clampedFatigue = fatigue.clamp(1.0, 3.0);

    // 소수점 3자리로 반올림
    final roundedFatigue = double.parse(clampedFatigue.toStringAsFixed(3));

    return roundedFatigue;
  }

  /// 피로도 레벨 텍스트 반환
  static String getFatigueLevel(double fatigue) {
    if (fatigue < 1.1) return '정상';
    if (fatigue < 1.4) return '약간 피로';
    if (fatigue < 1.8) return '피로 누적';
    return '고피로';
  }

  /// 피로도 레벨 색상 반환 (통일된 색상 사용)
  static Color getFatigueColor(double fatigue) {
    if (fatigue < 1.1) return const Color(0xFF4CAF50); // 초록 (정상)
    if (fatigue < 1.4) return const Color(0xFFFFA726); // 주황 (약간 피로)
    if (fatigue < 1.8) return const Color(0xFFFF7043); // 진한 주황 (피로 누적)
    return const Color(0xFFE53935); // 빨강 (고피로)
  }

  /// 게이지 값 변환 (0-100%)
  static double fatigueToGauge(double fatigue) {
    double value = ((fatigue - 1.0) * 100);
    if (value < 0) value = 0;
    if (value > 100) value = 100;
    return value;
  }

  /// 변화량 분석 (트렌드)
  static String getFatigueTrend(double prev, double current) {
    final delta = current - prev;

    if (delta.abs() < 0.1) return '변화 없음';
    if (delta > 0.3) return '피로도 급상승';
    if (delta > 0.1) return '피로 상승';
    if (delta < -0.1) return '회복 중';
    return '유지';
  }

  /// 트렌드 아이콘
  static IconData getFatigueTrendIcon(double prev, double current) {
    final delta = current - prev;

    if (delta.abs() < 0.1) return Icons.horizontal_rule;
    if (delta > 0.3) return Icons.trending_up;
    if (delta > 0.1) return Icons.arrow_upward;
    if (delta < -0.1) return Icons.arrow_downward;
    return Icons.horizontal_rule;
  }
}
