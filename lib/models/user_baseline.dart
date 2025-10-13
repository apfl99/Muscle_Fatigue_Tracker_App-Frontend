/// 사용자 기준선(Baseline) 모델
class UserBaseline {
  final String userId;
  final double rmsBaseline;
  final double varianceBaseline;
  final double frequencyBaseline;
  final DateTime lastUpdated;
  final int measurementCount;

  UserBaseline({
    required this.userId,
    required this.rmsBaseline,
    required this.varianceBaseline,
    required this.frequencyBaseline,
    required this.lastUpdated,
    this.measurementCount = 0,
  });

  /// 새로운 측정값으로 baseline 업데이트 (지수 이동 평균)
  UserBaseline updateWith({
    required double newRms,
    required double newVariance,
    required double newFrequency,
    double alpha = 0.2, // 가중치 (0.2 = 20% 새 값, 80% 기존 값)
  }) {
    return UserBaseline(
      userId: userId,
      rmsBaseline: (1 - alpha) * rmsBaseline + alpha * newRms,
      varianceBaseline: (1 - alpha) * varianceBaseline + alpha * newVariance,
      frequencyBaseline: (1 - alpha) * frequencyBaseline + alpha * newFrequency,
      lastUpdated: DateTime.now(),
      measurementCount: measurementCount + 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'rmsBaseline': rmsBaseline,
        'varianceBaseline': varianceBaseline,
        'frequencyBaseline': frequencyBaseline,
        'lastUpdated': lastUpdated.toIso8601String(),
        'measurementCount': measurementCount,
      };

  factory UserBaseline.fromJson(Map<String, dynamic> json) => UserBaseline(
        userId: json['userId'] as String,
        rmsBaseline: (json['rmsBaseline'] as num).toDouble(),
        varianceBaseline: (json['varianceBaseline'] as num).toDouble(),
        frequencyBaseline: (json['frequencyBaseline'] as num).toDouble(),
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        measurementCount: json['measurementCount'] as int,
      );

  /// 기본 초기 baseline 생성
  factory UserBaseline.initial(String userId) => UserBaseline(
        userId: userId,
        rmsBaseline: 1.0,
        varianceBaseline: 1.0,
        frequencyBaseline: 10.0,
        lastUpdated: DateTime.now(),
        measurementCount: 0,
      );
}

