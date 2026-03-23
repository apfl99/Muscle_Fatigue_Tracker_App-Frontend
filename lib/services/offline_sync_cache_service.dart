import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/heatmap/model/heatmap_models.dart';
import 'supabase_service.dart';

class OfflineSyncCacheService {
  static const String _snapshotKey = 'offline_heatmap_snapshot_v1';
  static const String _queueKey = 'offline_workout_queue_v1';

  Future<void> saveSnapshot({
    required List<MuscleHeatmapEntry> heatmapEntries,
    required List<WorkoutLogRecord> workoutLogs,
    required Map<String, MuscleRecoverySnapshot> recoveryByCode,
  }) async {
    final payload = <String, dynamic>{
      'saved_at': DateTime.now().toIso8601String(),
      'heatmap_entries': heatmapEntries.map(_encodeHeatmapEntry).toList(),
      'workout_logs': workoutLogs.map(_encodeWorkoutLog).toList(),
      'recovery': recoveryByCode.values.map(_encodeRecoverySnapshot).toList(),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(payload));
  }

  Future<OfflineHeatmapSnapshot?> readSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final data = Map<String, dynamic>.from(decoded);
      final entries = _decodeMapList(data['heatmap_entries'])
          .map(_decodeHeatmapEntry)
          .toList();
      final logs =
          _decodeMapList(data['workout_logs']).map(_decodeWorkoutLog).toList();
      final recoveryRows = _decodeMapList(data['recovery'])
          .map(_decodeRecoverySnapshot)
          .toList();
      final recoveryByCode = <String, MuscleRecoverySnapshot>{
        for (final row in recoveryRows) row.muscleCode: row,
      };
      final savedAt = _parseDateTime(data['saved_at']);
      return OfflineHeatmapSnapshot(
        savedAt: savedAt,
        heatmapEntries: entries,
        workoutLogs: logs,
        recoveryByCode: recoveryByCode,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> enqueueWorkoutDraft(WorkoutLogDraft draft) async {
    final queue = await readWorkoutQueue();
    queue.add(
      QueuedWorkoutDraft(
        id: _buildQueueId(),
        queuedAt: DateTime.now(),
        draft: draft,
      ),
    );
    await _saveWorkoutQueue(queue);
  }

  Future<List<QueuedWorkoutDraft>> readWorkoutQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.trim().isEmpty) {
      return <QueuedWorkoutDraft>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <QueuedWorkoutDraft>[];
      }
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map(_decodeQueuedWorkoutDraft)
          .toList();
    } catch (_) {
      return <QueuedWorkoutDraft>[];
    }
  }

  Future<void> replaceWorkoutQueue(List<QueuedWorkoutDraft> queue) {
    return _saveWorkoutQueue(queue);
  }

  Future<void> _saveWorkoutQueue(List<QueuedWorkoutDraft> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = queue.map(_encodeQueuedWorkoutDraft).toList();
    await prefs.setString(_queueKey, jsonEncode(encoded));
  }

  String _buildQueueId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now % 9973;
    return 'offline_$now$rand';
  }

  Map<String, dynamic> _encodeHeatmapEntry(MuscleHeatmapEntry entry) {
    return <String, dynamic>{
      'muscle_code': entry.muscleCode,
      'status': entry.status.rawValue,
      'scores': entry.scores,
      'fatigue_score': entry.fatigueScore,
      'display_score': entry.displayScore,
      'last_trained_at': entry.lastTrainedAt?.toIso8601String(),
      'display_name_ko': entry.displayNameKo,
      'display_name_latin': entry.displayNameLatin,
      'anatomy_id': entry.anatomyId,
      'parent_muscle_code': entry.parentMuscleCode,
      'side': entry.side,
    };
  }

  MuscleHeatmapEntry _decodeHeatmapEntry(Map<String, dynamic> json) {
    final rawScores = (json['scores'] as List?) ?? const <Object>[];
    return MuscleHeatmapEntry(
      muscleCode: (json['muscle_code'] as String? ?? '').trim(),
      status: HeatmapStatusParser.fromRaw(json['status'] as String?),
      scores: rawScores
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
      fatigueScore: (json['fatigue_score'] as num?)?.toDouble() ?? 0,
      displayScore: (json['display_score'] as num?)?.toInt() ?? 0,
      lastTrainedAt: _parseDateTimeNullable(json['last_trained_at']),
      displayNameKo: (json['display_name_ko'] as String?)?.trim(),
      displayNameLatin: (json['display_name_latin'] as String?)?.trim(),
      anatomyId: (json['anatomy_id'] as String?)?.trim(),
      parentMuscleCode: (json['parent_muscle_code'] as String?)?.trim(),
      side: (json['side'] as String? ?? 'bilateral').trim(),
    );
  }

  Map<String, dynamic> _encodeWorkoutLog(WorkoutLogRecord row) {
    return <String, dynamic>{
      'id': row.id,
      'exercise_id': row.exerciseId,
      'exercise_name': row.exerciseName,
      'category': row.category,
      'exercise_type': row.exerciseType.rawValue,
      'muscle_size': row.muscleSize.rawValue,
      'performed_at': row.performedAt.toIso8601String(),
      'primary_muscles': row.primaryMuscles,
      'secondary_muscles': row.secondaryMuscles,
      'sets': row.sets,
      'reps': row.reps,
      'weight_kg': row.weightKg,
      'duration_minutes': row.durationMinutes,
      'distance_km': row.distanceKm,
      'note': row.note,
    };
  }

  WorkoutLogRecord _decodeWorkoutLog(Map<String, dynamic> json) {
    return WorkoutLogRecord(
      id: (json['id'] as String? ?? '').trim(),
      exerciseId: (json['exercise_id'] as String? ?? '').trim(),
      exerciseName: (json['exercise_name'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      exerciseType:
          ExerciseTypeParser.fromRaw(json['exercise_type'] as String?),
      muscleSize: MuscleSizeParser.fromRaw(json['muscle_size'] as String?),
      performedAt: _parseDateTime(json['performed_at']),
      primaryMuscles: ((json['primary_muscles'] as List?) ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false),
      secondaryMuscles:
          ((json['secondary_muscles'] as List?) ?? const <Object>[])
              .whereType<String>()
              .toList(growable: false),
      sets: (json['sets'] as num?)?.toInt(),
      reps: (json['reps'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      note: (json['note'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> _encodeRecoverySnapshot(MuscleRecoverySnapshot row) {
    return <String, dynamic>{
      'muscle_code': row.muscleCode,
      'display_name': row.displayName,
      'muscle_size': row.muscleSize.rawValue,
      'last_worked_at': row.lastWorkedAt.toIso8601String(),
    };
  }

  MuscleRecoverySnapshot _decodeRecoverySnapshot(Map<String, dynamic> json) {
    return MuscleRecoverySnapshot(
      muscleCode: (json['muscle_code'] as String? ?? '').trim().toLowerCase(),
      displayName: (json['display_name'] as String? ?? '').trim(),
      muscleSize: MuscleSizeParser.fromRaw(json['muscle_size'] as String?),
      lastWorkedAt: _parseDateTime(json['last_worked_at']),
    );
  }

  Map<String, dynamic> _encodeQueuedWorkoutDraft(QueuedWorkoutDraft row) {
    return <String, dynamic>{
      'id': row.id,
      'queued_at': row.queuedAt.toIso8601String(),
      'draft': _encodeDraft(row.draft),
    };
  }

  QueuedWorkoutDraft _decodeQueuedWorkoutDraft(Map<String, dynamic> json) {
    final draftNode = json['draft'];
    final draft = draftNode is Map
        ? _decodeDraft(Map<String, dynamic>.from(draftNode))
        : _decodeDraft(const <String, dynamic>{});
    return QueuedWorkoutDraft(
      id: (json['id'] as String? ?? _buildQueueId()).trim(),
      queuedAt: _parseDateTime(json['queued_at']),
      draft: draft,
    );
  }

  Map<String, dynamic> _encodeDraft(WorkoutLogDraft draft) {
    return <String, dynamic>{
      'exercise_id': draft.exerciseId,
      'sets': draft.sets,
      'reps': draft.reps,
      'weight_kg': draft.weightKg,
      'duration_minutes': draft.durationMinutes,
      'distance_km': draft.distanceKm,
      'note': draft.note,
      'performed_at': draft.performedAt?.toIso8601String(),
    };
  }

  WorkoutLogDraft _decodeDraft(Map<String, dynamic> json) {
    return WorkoutLogDraft(
      exerciseId: (json['exercise_id'] as String? ?? '').trim(),
      sets: (json['sets'] as num?)?.toInt(),
      reps: (json['reps'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      note: (json['note'] as String?)?.trim(),
      performedAt: _parseDateTimeNullable(json['performed_at']),
    );
  }

  List<Map<String, dynamic>> _decodeMapList(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  DateTime _parseDateTime(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return DateTime.now();
  }

  DateTime? _parseDateTimeNullable(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }
    return null;
  }
}

class OfflineHeatmapSnapshot {
  const OfflineHeatmapSnapshot({
    required this.savedAt,
    required this.heatmapEntries,
    required this.workoutLogs,
    required this.recoveryByCode,
  });

  final DateTime savedAt;
  final List<MuscleHeatmapEntry> heatmapEntries;
  final List<WorkoutLogRecord> workoutLogs;
  final Map<String, MuscleRecoverySnapshot> recoveryByCode;
}

class QueuedWorkoutDraft {
  const QueuedWorkoutDraft({
    required this.id,
    required this.queuedAt,
    required this.draft,
  });

  final String id;
  final DateTime queuedAt;
  final WorkoutLogDraft draft;
}
