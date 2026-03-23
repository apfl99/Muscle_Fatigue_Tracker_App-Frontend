import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../models/exercise.dart';

class WorkoutLogRecord {
  const WorkoutLogRecord({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.exerciseType,
    required this.muscleSize,
    required this.performedAt,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.sets,
    this.reps,
    this.weightKg,
    this.durationMinutes,
    this.distanceKm,
    this.note,
  });

  final String id;
  final String exerciseId;
  final String exerciseName;
  final String category;
  final ExerciseType exerciseType;
  final MuscleSize muscleSize;
  final DateTime performedAt;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final int? sets;
  final int? reps;
  final double? weightKg;
  final int? durationMinutes;
  final double? distanceKm;
  final String? note;

  factory WorkoutLogRecord.fromJson(Map<String, dynamic> json) {
    final exercise = _parseExerciseNode(json['exercises']);
    return WorkoutLogRecord(
      id: (json['id'] as String? ?? '').trim(),
      exerciseId: (json['exercise_id'] as String? ?? '').trim(),
      exerciseName: (exercise['name'] as String? ?? '알 수 없는 운동'),
      category: (exercise['category'] as String? ?? 'unknown'),
      exerciseType:
          (exercise['exercise_type'] as ExerciseType? ?? ExerciseType.unknown),
      muscleSize:
          (exercise['muscle_size'] as MuscleSize? ?? MuscleSize.unknown),
      primaryMuscles:
          (exercise['primary_muscles'] as List<String>?) ?? const <String>[],
      secondaryMuscles:
          (exercise['secondary_muscles'] as List<String>?) ?? const <String>[],
      performedAt: _parseDateTime(json['performed_at']),
      sets: (json['sets'] as num?)?.toInt(),
      reps: (json['reps'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      note: (json['note'] as String?)?.trim(),
    );
  }

  static Map<String, dynamic> _parseExerciseNode(dynamic rawExercise) {
    if (rawExercise is Map) {
      return _normalizeExercise(rawExercise);
    }

    if (rawExercise is List &&
        rawExercise.isNotEmpty &&
        rawExercise.first is Map) {
      return _normalizeExercise(rawExercise.first as Map);
    }

    return {
      'name': '알 수 없는 운동',
      'category': 'unknown',
      'exercise_type': ExerciseType.unknown,
      'muscle_size': MuscleSize.unknown,
      'primary_muscles': const <String>[],
      'secondary_muscles': const <String>[],
    };
  }

  static Map<String, dynamic> _normalizeExercise(Map rawExercise) {
    final exercise =
        ExerciseModel.fromJson(Map<String, dynamic>.from(rawExercise));
    return {
      'name': exercise.name,
      'category': exercise.category,
      'exercise_type': ExerciseTypeParser.fromRaw(exercise.exerciseTypeRaw),
      'muscle_size': MuscleSizeParser.fromRaw(exercise.muscleSizeRaw),
      'primary_muscles': exercise.primaryMuscles,
      'secondary_muscles': exercise.secondaryMuscles,
    };
  }

  static DateTime _parseDateTime(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return DateTime.now();
  }
}

class SupabaseService {
  SupabaseService({
    SupabaseClient? client,
  }) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<String> getCurrentUserId() async {
    final user = await _requireAuthenticatedUser();
    return user.id;
  }

  Future<List<MuscleHeatmapEntry>> getMuscleHeatmapStatus() async {
    final response = await _runWithSessionRetry<dynamic>((user) {
      return _client.rpc(
        'get_muscle_heatmap_status',
        params: {'p_user_id': user.id},
      );
    });
    return _decodeMapList(response)
        .map(MuscleHeatmapEntry.fromJson)
        .where((entry) => entry.muscleCode.isNotEmpty)
        .toList();
  }

  Future<List<ExerciseSuggestion>> searchExercises({
    required String keyword,
  }) async {
    if (keyword.trim().isEmpty) {
      return const [];
    }

    final response = await _runWithSessionRetry<dynamic>((_) {
      // 사용자 입력 원문(영문/한글/초성)을 그대로 서버에 전달한다.
      return _client.rpc(
        'search_exercises',
        params: {'p_keyword': keyword},
      );
    });
    return _decodeMapList(response)
        .map(ExerciseSuggestion.fromJson)
        .where((entry) => entry.id.isNotEmpty && entry.name.isNotEmpty)
        .toList();
  }

  Future<void> insertWorkoutLog({
    required WorkoutLogDraft draft,
  }) async {
    await _runWithSessionRetry<void>((user) async {
      await _client
          .from('workout_logs')
          .insert(draft.toInsertPayload(userId: user.id));
    });
  }

  Future<List<WorkoutLogRecord>> fetchWorkoutLogs({int limit = 30}) async {
    final response = await _runWithSessionRetry<dynamic>((user) {
      return _client
          .from('workout_logs')
          .select(
            'id, exercise_id, sets, reps, weight_kg, duration_minutes, distance_km, note, performed_at, exercises(name, category, exercise_type, muscle_size, primary_muscles, secondary_muscles)',
          )
          .eq('user_id', user.id)
          .order('performed_at', ascending: false)
          .limit(limit);
    });

    return _decodeMapList(response)
        .map(WorkoutLogRecord.fromJson)
        .where((entry) => entry.id.isNotEmpty && entry.exerciseId.isNotEmpty)
        .toList();
  }

  Future<List<MuscleRecoverySnapshot>> fetchMuscleRecoverySnapshots({
    int limit = 120,
  }) async {
    final response = await _runWithSessionRetry<dynamic>((user) {
      return _client
          .from('workout_logs')
          .select(
            'performed_at, exercises!inner(muscle_size, exercise_muscle_mapping!inner(muscles!inner(code, display_name_ko, display_name)))',
          )
          .eq('user_id', user.id)
          .order('performed_at', ascending: false)
          .limit(limit);
    });

    final snapshotsByCode = <String, MuscleRecoverySnapshot>{};
    for (final row in _decodeMapList(response)) {
      final performedAt = _parseDateTime(row['performed_at']);
      final exerciseNode = _extractSingleMap(row['exercises']);
      if (exerciseNode == null) {
        continue;
      }

      final muscleSize =
          MuscleSizeParser.fromRaw(exerciseNode['muscle_size'] as String?);
      final mappings = _extractMapList(exerciseNode['exercise_muscle_mapping']);
      for (final mapping in mappings) {
        final muscleNode = _extractSingleMap(mapping['muscles']);
        if (muscleNode == null) {
          continue;
        }

        final muscleCode =
            (muscleNode['code'] as String? ?? '').trim().toLowerCase();
        if (muscleCode.isEmpty) {
          continue;
        }

        final displayName = _sanitizeMuscleDisplayName(
              (muscleNode['display_name_ko'] as String? ??
                      muscleNode['display_name'] as String?)
                  ?.replaceAll('\n', ' '),
            ) ??
            muscleCode;
        final current = snapshotsByCode[muscleCode];
        if (current == null || performedAt.isAfter(current.lastWorkedAt)) {
          snapshotsByCode[muscleCode] = MuscleRecoverySnapshot(
            muscleCode: muscleCode,
            displayName: displayName,
            muscleSize: muscleSize,
            lastWorkedAt: performedAt,
          );
        }
      }
    }

    final snapshots = snapshotsByCode.values.toList()
      ..sort((a, b) => b.lastWorkedAt.compareTo(a.lastWorkedAt));
    return snapshots;
  }

  Future<T> _runWithSessionRetry<T>(
    Future<T> Function(User user) action,
  ) async {
    var user = await _requireAuthenticatedUser();
    try {
      return await action(user);
    } on PostgrestException catch (error) {
      if (_isUnauthorized(error)) {
        user = await _refreshAnonymousSession();
        return await action(user);
      }
      rethrow;
    } on AuthException {
      user = await _refreshAnonymousSession();
      return await action(user);
    }
  }

  Future<User> _requireAuthenticatedUser() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser != null) {
      return currentUser;
    }

    try {
      final response = await _client.auth.getUser();
      final user = response.user;
      if (user != null) {
        return user;
      }
    } on AuthException {
      // 아래 익명 세션 생성으로 복구 시도
    } catch (_) {
      // 아래 익명 세션 생성으로 복구 시도
    }

    return _signInAnonymously();
  }

  Future<User> _refreshAnonymousSession() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // signOut 실패해도 익명 재로그인을 계속 시도한다.
    }
    return _signInAnonymously();
  }

  Future<User> _signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    final user = response.user;
    if (user == null) {
      throw const AuthException('익명 세션 생성에 실패했습니다.');
    }
    return user;
  }

  bool _isUnauthorized(PostgrestException error) {
    final code = error.code?.trim().toUpperCase();
    if (code == '401' || code == 'PGRST301' || code == 'PGRST302') {
      return true;
    }

    final message = error.message.toLowerCase();
    return message.contains('401') ||
        message.contains('unauthorized') ||
        message.contains('jwt');
  }

  List<Map<String, dynamic>> _decodeMapList(dynamic response) {
    if (response is! List) {
      return const [];
    }
    return response
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  List<Map<String, dynamic>> _extractMapList(dynamic rawValue) {
    if (rawValue is List) {
      return rawValue
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    if (rawValue is Map) {
      return <Map<String, dynamic>>[Map<String, dynamic>.from(rawValue)];
    }
    return const [];
  }

  Map<String, dynamic>? _extractSingleMap(dynamic rawValue) {
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    if (rawValue is List && rawValue.isNotEmpty && rawValue.first is Map) {
      return Map<String, dynamic>.from(rawValue.first as Map);
    }
    return null;
  }

  DateTime _parseDateTime(dynamic rawValue) {
    if (rawValue is String) {
      final parsed = DateTime.tryParse(rawValue);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return DateTime.now();
  }

  String? _sanitizeMuscleDisplayName(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final compact = value.toLowerCase().replaceAll(RegExp(r'[\s_\-./]'), '');
    const placeholders = <String>{
      '근육부위',
      '기타근육',
      '알수없음',
      '알수없는근육',
      'unknown',
      'other',
      'muscle',
      'muscles',
      'na',
      'none',
      'null',
    };
    if (placeholders.contains(compact)) {
      return null;
    }
    return value;
  }
}
