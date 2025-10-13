/// 근피로도 측정 결과 모델
class FatigueResult {
  final String id;
  final DateTime timestamp;
  final double fatigueIndex; // 0~10
  final double rms;
  final double variance;
  final double dominantFrequency;
  final String? userId;

  FatigueResult({
    required this.id,
    required this.timestamp,
    required this.fatigueIndex,
    required this.rms,
    required this.variance,
    required this.dominantFrequency,
    this.userId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'fatigueIndex': fatigueIndex,
        'rms': rms,
        'variance': variance,
        'dominantFrequency': dominantFrequency,
        'userId': userId,
      };

  factory FatigueResult.fromJson(Map<String, dynamic> json) => FatigueResult(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        fatigueIndex: (json['fatigueIndex'] as num).toDouble(),
        rms: (json['rms'] as num).toDouble(),
        variance: (json['variance'] as num).toDouble(),
        dominantFrequency: (json['dominantFrequency'] as num).toDouble(),
        userId: json['userId'] as String?,
      );

  /// 피로도 레벨 문자열 반환 (낮음/보통/높음/매우 높음)
  String get fatigueLevel {
    if (fatigueIndex < 3) return '낮음';
    if (fatigueIndex < 6) return '보통';
    if (fatigueIndex < 8) return '높음';
    return '매우 높음';
  }
}

