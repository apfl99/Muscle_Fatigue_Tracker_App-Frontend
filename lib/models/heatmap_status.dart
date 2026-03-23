class HeatmapStatusModel {
  const HeatmapStatusModel({
    required this.muscleCode,
    required this.statusRaw,
    required this.scores,
    required this.fatigueScoreRaw,
    required this.lastTrainedAt,
    required this.side,
    this.displayNameKo,
    this.displayNameLatin,
    this.anatomyId,
    this.parentMuscleCode,
  });

  final String muscleCode;
  final String statusRaw;
  final List<double> scores;
  final double? fatigueScoreRaw;
  final DateTime? lastTrainedAt;
  final String? displayNameKo;
  final String? displayNameLatin;
  final String? anatomyId;
  final String? parentMuscleCode;
  final String side;

  // 레거시 호출부 호환을 위해 유지한다.
  String get muscleId => muscleCode;

  factory HeatmapStatusModel.fromJson(Map<String, dynamic> json) {
    final scores = _parseScores(json['scores'] ?? json['score']);
    final fatigueScoreRaw = (json['fatigue_score'] as num?)?.toDouble() ??
        (json['score'] is num ? (json['score'] as num).toDouble() : null);
    final rawCode = (json['muscle_code'] as String? ??
            json['muscle_id'] as String? ??
            json['muscle'] as String? ??
            '')
        .trim()
        .toLowerCase();
    final parentCode = _sanitizeMuscleCode(
      (json['parent_muscle_code'] as String? ?? '').trim().toLowerCase(),
    );
    final displayNameKo = _sanitizeDisplayName(
      (json['display_name_ko'] as String? ?? json['display_name'] as String?),
    );

    return HeatmapStatusModel(
      muscleCode: _sanitizeMuscleCode(rawCode),
      statusRaw: (json['status'] as String? ?? '').trim().toLowerCase(),
      scores: scores,
      fatigueScoreRaw: fatigueScoreRaw,
      lastTrainedAt: _parseDateTime(
        json['last_trained_at'] ?? json['last_worked_at'],
      ),
      displayNameKo: displayNameKo,
      displayNameLatin: _sanitizeOptionalText(json['display_name_latin']),
      anatomyId: _sanitizeOptionalText(json['anatomy_id']),
      parentMuscleCode: parentCode.isEmpty ? null : parentCode,
      side: _sanitizeSide(json['side']),
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

  static String _sanitizeMuscleCode(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    if (!_muscleCodePattern.hasMatch(raw)) {
      return '';
    }
    return raw;
  }

  static String? _sanitizeDisplayName(String? raw) {
    final value = _sanitizeOptionalText(raw);
    if (value == null) {
      return null;
    }
    if (_isPlaceholderDisplayName(value)) {
      return null;
    }
    return value;
  }

  static String? _sanitizeOptionalText(dynamic raw) {
    if (raw is! String) {
      return null;
    }
    final normalized = raw.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String _sanitizeSide(dynamic raw) {
    final normalized = (raw as String? ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'left':
      case 'right':
      case 'bilateral':
      case 'unknown':
        return normalized;
      default:
        return 'bilateral';
    }
  }

  static bool _isPlaceholderDisplayName(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'[\s_\-./]'), '');
    return _placeholderDisplayNames.contains(compact);
  }
}

final RegExp _muscleCodePattern = RegExp(r'^[a-z0-9_]+$');

const Set<String> _placeholderDisplayNames = {
  '근육부위',
  '기타근육',
  '알수없음',
  '알수없는근육',
  'unknown',
  'other',
  'muscle',
  'muscles',
  'na',
  'n/a',
  'none',
  'null',
};
