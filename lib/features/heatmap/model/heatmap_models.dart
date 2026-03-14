import '../../../models/exercise.dart';
import '../../../models/heatmap_status.dart';

enum HeatmapStatus {
  red,
  yellow,
  green,
  unknown,
}

enum ExerciseType {
  cardio,
  weight,
  unknown,
}

extension ExerciseTypeParser on ExerciseType {
  static ExerciseType fromRaw(String? rawType) {
    switch (rawType?.trim().toLowerCase()) {
      case 'cardio':
        return ExerciseType.cardio;
      case 'weight':
        return ExerciseType.weight;
      default:
        return ExerciseType.unknown;
    }
  }

  String get rawValue {
    switch (this) {
      case ExerciseType.cardio:
        return 'cardio';
      case ExerciseType.weight:
        return 'weight';
      case ExerciseType.unknown:
        return 'unknown';
    }
  }
}

enum MuscleSize {
  large,
  small,
  unknown,
}

extension MuscleSizeParser on MuscleSize {
  static MuscleSize fromRaw(String? rawSize) {
    switch (rawSize?.trim().toLowerCase()) {
      case 'large':
        return MuscleSize.large;
      case 'small':
        return MuscleSize.small;
      default:
        return MuscleSize.unknown;
    }
  }

  String get rawValue {
    switch (this) {
      case MuscleSize.large:
        return 'large';
      case MuscleSize.small:
        return 'small';
      case MuscleSize.unknown:
        return 'unknown';
    }
  }
}

extension HeatmapStatusParser on HeatmapStatus {
  static HeatmapStatus fromRaw(String? rawStatus) {
    switch (rawStatus?.trim().toLowerCase()) {
      case 'red':
        return HeatmapStatus.red;
      case 'yellow':
        return HeatmapStatus.yellow;
      case 'green':
        return HeatmapStatus.green;
      default:
        return HeatmapStatus.unknown;
    }
  }

  String get rawValue {
    switch (this) {
      case HeatmapStatus.red:
        return 'red';
      case HeatmapStatus.yellow:
        return 'yellow';
      case HeatmapStatus.green:
        return 'green';
      case HeatmapStatus.unknown:
        return 'unknown';
    }
  }
}

class MuscleHeatmapEntry {
  const MuscleHeatmapEntry({
    required this.muscleCode,
    required this.status,
    this.scores = const [],
    this.fatigueScore = 0,
    this.displayScore = 0,
    this.lastTrainedAt,
  });

  final String muscleCode;
  final HeatmapStatus status;
  final List<double> scores;
  final double fatigueScore;
  final int displayScore;
  final DateTime? lastTrainedAt;

  double get conditionScore => fatigueScore;

  int get conditionDisplayScore => displayScore;

  factory MuscleHeatmapEntry.fromJson(Map<String, dynamic> json) {
    final payload = HeatmapStatusModel.fromJson(json);
    final normalizedCode = _normalizeMuscleCode(payload.muscleId);
    final resolvedStatusRaw = payload.statusRaw.isNotEmpty
        ? payload.statusRaw
        : _statusFromScore(payload.normalizedFatigueScore);
    return MuscleHeatmapEntry(
      muscleCode: normalizedCode,
      status: HeatmapStatusParser.fromRaw(resolvedStatusRaw),
      scores: payload.scores,
      fatigueScore: payload.normalizedFatigueScore,
      displayScore: payload.displayScore,
      lastTrainedAt: payload.lastTrainedAt,
    );
  }

  static String _statusFromScore(double score) {
    if (score >= 1.6) {
      return 'red';
    }
    if (score >= 0.8) {
      return 'yellow';
    }
    return 'green';
  }

  static String _normalizeMuscleCode(String muscleCode) {
    final normalized = muscleCode.trim().toLowerCase();
    if (normalized.isEmpty) {
      return normalized;
    }
    return _muscleCodeAliases[normalized] ?? normalized;
  }

  static const Map<String, String> _muscleCodeAliases = {
    'anterior_deltoid': 'front_deltoid',
    'front_delts': 'front_deltoid',
    'side_deltoid': 'lateral_deltoid',
    'lateral_delts': 'lateral_deltoid',
    'posterior_deltoid': 'rear_deltoid',
    'rear_delts': 'rear_deltoid',
    'quads': 'quadriceps',
    'lats': 'latissimus',
    'latissimus_dorsi': 'latissimus',
    'abs': 'rectus_abdominis',
    'abdominals': 'rectus_abdominis',
    'pectoralis_major': 'chest',
    'pecs': 'chest',
    'gastrocnemius_medial': 'gastrocnemius',
    'gastrocnemius_lateral': 'gastrocnemius',
    'spinal_erectors': 'erector_spinae',
    'erectors': 'erector_spinae',
    'lumbar': 'lower_back',
    'wrist_flexor': 'forearm_flexor',
    'wrist_extensor': 'forearm_extensor',
    'forearm': 'forearm_flexor',
    'forearms': 'forearm_flexor',
    'biceps_brachii': 'biceps',
  };
}

class ExerciseSuggestion {
  const ExerciseSuggestion({
    required this.id,
    required this.name,
    required this.category,
    required this.exerciseType,
    required this.muscleSize,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
  });

  final String id;
  final String name;
  final String category;
  final ExerciseType exerciseType;
  final MuscleSize muscleSize;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  factory ExerciseSuggestion.fromJson(Map<String, dynamic> json) {
    final exercise = ExerciseModel.fromJson(json);
    return ExerciseSuggestion(
      id: exercise.id,
      name: exercise.name,
      category: exercise.category,
      exerciseType: ExerciseTypeParser.fromRaw(exercise.exerciseTypeRaw),
      muscleSize: MuscleSizeParser.fromRaw(exercise.muscleSizeRaw),
      primaryMuscles: exercise.primaryMuscles,
      secondaryMuscles: exercise.secondaryMuscles,
    );
  }
}

class WorkoutLogDraft {
  const WorkoutLogDraft({
    required this.exerciseId,
    this.sets,
    this.reps,
    this.weightKg,
    this.durationMinutes,
    this.distanceKm,
    this.note,
    this.performedAt,
  });

  final String exerciseId;
  final int? sets;
  final int? reps;
  final double? weightKg;
  final int? durationMinutes;
  final double? distanceKm;
  final String? note;
  final DateTime? performedAt;

  Map<String, dynamic> toInsertPayload({required String userId}) {
    final payload = <String, dynamic>{
      'user_id': userId,
      'exercise_id': exerciseId,
      'sets': sets,
      'reps': reps,
      'weight_kg': weightKg,
      'duration_minutes': durationMinutes,
      'distance_km': distanceKm,
      'note': note,
      'performed_at': (performedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };

    if ((payload['note'] as String?)?.trim().isEmpty ?? true) {
      payload.remove('note');
    }

    return payload;
  }
}

class MuscleRecoverySnapshot {
  const MuscleRecoverySnapshot({
    required this.muscleCode,
    required this.displayName,
    required this.muscleSize,
    required this.lastWorkedAt,
  });

  final String muscleCode;
  final String displayName;
  final MuscleSize muscleSize;
  final DateTime lastWorkedAt;
}

class MeasurementBridgePayload {
  const MeasurementBridgePayload({
    required this.measuredAt,
    required this.fatigueScore,
    this.fatigueVariance,
    this.peakFrequency,
  });

  final DateTime measuredAt;
  final double fatigueScore;
  final double? fatigueVariance;
  final double? peakFrequency;

  factory MeasurementBridgePayload.fromAnalysisResult(
    Map<String, dynamic> analysisResult,
  ) {
    return MeasurementBridgePayload(
      measuredAt: _parseDateTime(analysisResult['timestamp']),
      fatigueScore: (analysisResult['fatigueScore'] as num?)?.toDouble() ?? 0.0,
      fatigueVariance: (analysisResult['fatigueVariance'] as num?)?.toDouble(),
      peakFrequency: (analysisResult['peakFreq'] as num?)?.toDouble(),
    );
  }

  static DateTime _parseDateTime(dynamic raw) {
    if (raw is DateTime) {
      return raw;
    }

    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }

    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }

    return DateTime.now();
  }
}
