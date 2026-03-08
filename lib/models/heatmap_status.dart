class HeatmapStatusModel {
  const HeatmapStatusModel({
    required this.muscleId,
    required this.statusRaw,
    required this.scores,
    required this.fatigueScoreRaw,
    required this.lastTrainedAt,
  });

  final String muscleId;
  final String statusRaw;
  final List<double> scores;
  final double? fatigueScoreRaw;
  final DateTime? lastTrainedAt;

  factory HeatmapStatusModel.fromJson(Map<String, dynamic> json) {
    final scores = _parseScores(json['scores'] ?? json['score']);
    final fatigueScoreRaw = (json['fatigue_score'] as num?)?.toDouble() ??
        (json['score'] is num ? (json['score'] as num).toDouble() : null);

    return HeatmapStatusModel(
      muscleId:
          (json['muscle_id'] as String? ?? json['muscle'] as String? ?? '')
              .trim()
              .toLowerCase(),
      statusRaw: (json['status'] as String? ?? '').trim().toLowerCase(),
      scores: scores,
      fatigueScoreRaw: fatigueScoreRaw,
      lastTrainedAt: _parseDateTime(
        json['last_trained_at'] ?? json['last_worked_at'],
      ),
    );
  }

  double get normalizedFatigueScore {
    final resolvedRawScore = fatigueScoreRaw ?? _average(scores);
    if (resolvedRawScore <= 0) {
      return 0;
    }

    if (resolvedRawScore > 3.0) {
      return (resolvedRawScore / 100.0 * 3.0).clamp(0.0, 3.0);
    }
    return resolvedRawScore.clamp(0.0, 3.0);
  }

  int get displayScore {
    final resolvedRawScore = fatigueScoreRaw ?? _average(scores);
    if (resolvedRawScore > 3.0) {
      return resolvedRawScore.round().clamp(0, 100);
    }
    return ((normalizedFatigueScore / 3.0) * 100.0).round().clamp(0, 100);
  }

  static List<double> _parseScores(dynamic raw) {
    if (raw is List) {
      return raw
          .map((entry) => (entry as num?)?.toDouble())
          .whereType<double>()
          .toList();
    }
    if (raw is num) {
      return <double>[raw.toDouble()];
    }
    return const [];
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return null;
  }

  static double _average(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }
}
