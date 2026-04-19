import '../features/heatmap/model/muscle_taxonomy.dart';

class ExerciseModel {
  const ExerciseModel({
    required this.id,
    required this.name,
    required this.category,
    required this.exerciseTypeRaw,
    required this.muscleSizeRaw,
    required this.primaryMuscles,
    required this.secondaryMuscles,
  });

  final String id;
  final String name;
  final String category;
  final String exerciseTypeRaw;
  final String muscleSizeRaw;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  factory ExerciseModel.fromJson(Map<String, dynamic> json) {
    return ExerciseModel(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      exerciseTypeRaw: (json['exercise_type'] as String? ?? '').trim(),
      muscleSizeRaw: (json['muscle_size'] as String? ?? '').trim(),
      primaryMuscles: parseMuscleList(json['primary_muscles']),
      secondaryMuscles: parseMuscleList(json['secondary_muscles']),
    );
  }

  static List<String> parseMuscleList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    final values = <String>[];
    for (final entry in raw) {
      final normalized = normalizeCanonicalMuscleCode('$entry');
      if (normalized.isEmpty) {
        continue;
      }
      values.add(normalized);
    }
    return values.toSet().toList();
  }
}
