/// User Stats 모델 (user_stats 테이블)
/// 최근 N회 측정 기반 통계 (user embedding 계산용)
class UserStats {
  final int sampleWindow; // 최근 N회 사용 기준
  final int measCount; // 실제 측정 횟수
  final double rmsMean;
  final double freqMean;
  final double rmsVar;
  final double freqVar;
  final double fatigueMean;
  final double fatigueCv; // Coefficient of Variation
  final double driftRms; // RMS 변화량 (vs baseline)
  final double driftFreq; // Freq 변화량 (vs baseline)
  final double timeOfDayMean; // 평균 측정 시간대 (0~1 정규화)
  final double sessionLenMean; // 평균 세션 길이(초)
  final DateTime? updatedAt;

  UserStats({
    this.sampleWindow = 5,
    this.measCount = 0,
    this.rmsMean = 0.0,
    this.freqMean = 0.0,
    this.rmsVar = 0.0,
    this.freqVar = 0.0,
    this.fatigueMean = 1.0,
    this.fatigueCv = 0.0,
    this.driftRms = 0.0,
    this.driftFreq = 0.0,
    this.timeOfDayMean = 0.0,
    this.sessionLenMean = 0.0,
    this.updatedAt,
  });

  /// DB에서 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'sample_window': sampleWindow,
      'meas_count': measCount,
      'rms_mean': rmsMean,
      'freq_mean': freqMean,
      'rms_var': rmsVar,
      'freq_var': freqVar,
      'fatigue_mean': fatigueMean,
      'fatigue_cv': fatigueCv,
      'drift_rms': driftRms,
      'drift_freq': driftFreq,
      'time_of_day_mean': timeOfDayMean,
      'session_len_mean': sessionLenMean,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Map에서 생성
  factory UserStats.fromMap(Map<String, dynamic> map) {
    return UserStats(
      sampleWindow: map['sample_window'] as int? ?? 5,
      measCount: map['meas_count'] as int? ?? 0,
      rmsMean: map['rms_mean'] as double? ?? 0.0,
      freqMean: map['freq_mean'] as double? ?? 0.0,
      rmsVar: map['rms_var'] as double? ?? 0.0,
      freqVar: map['freq_var'] as double? ?? 0.0,
      fatigueMean: map['fatigue_mean'] as double? ?? 1.0,
      fatigueCv: map['fatigue_cv'] as double? ?? 0.0,
      driftRms: map['drift_rms'] as double? ?? 0.0,
      driftFreq: map['drift_freq'] as double? ?? 0.0,
      timeOfDayMean: map['time_of_day_mean'] as double? ?? 0.0,
      sessionLenMean: map['session_len_mean'] as double? ?? 0.0,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// User Embedding 생성 (12차원)
  /// DB_SCHEMA.md의 user_emb 계산 로직
  List<double> toUserEmbedding(double rmsBase, double freqBase) {
    return [
      rmsBase, // 0: rms_base
      freqBase, // 1: freq_base
      rmsVar, // 2: rms_var
      freqVar, // 3: freq_var
      measCount.toDouble(), // 4: meas_count
      fatigueMean, // 5: fatigue_mean
      fatigueCv, // 6: fatigue_cv
      driftRms, // 7: drift_rms
      driftFreq, // 8: drift_freq
      timeOfDayMean, // 9: time_of_day_mean
      sessionLenMean, // 10: session_len_mean
      sampleWindow.toDouble(), // 11: sample_window
    ];
  }

  @override
  String toString() {
    return 'UserStats{measCount: $measCount, fatigueMean: $fatigueMean, rmsMean: $rmsMean}';
  }
}
