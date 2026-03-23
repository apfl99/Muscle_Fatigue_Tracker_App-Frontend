import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/model/heatmap_models.dart';
import 'package:muscle_fatigue_tracker/services/offline_sync_cache_service.dart';
import 'package:muscle_fatigue_tracker/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineSyncCacheService', () {
    late OfflineSyncCacheService service;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = OfflineSyncCacheService();
    });

    test('snapshot 저장/복구 round-trip 동작', () async {
      final entries = <MuscleHeatmapEntry>[
        MuscleHeatmapEntry(
          muscleCode: 'chest',
          status: HeatmapStatus.yellow,
          displayScore: 61,
          fatigueScore: 1.72,
          lastTrainedAt: DateTime(2026, 3, 1, 10, 0),
          displayNameKo: '대흉근',
        ),
      ];
      final logs = <WorkoutLogRecord>[
        WorkoutLogRecord(
          id: 'local_1',
          exerciseId: 'bench_press',
          exerciseName: '벤치프레스',
          category: 'strength',
          exerciseType: ExerciseType.weight,
          muscleSize: MuscleSize.large,
          performedAt: DateTime(2026, 3, 1, 10, 30),
          sets: 4,
          reps: 10,
        ),
      ];
      final recovery = <String, MuscleRecoverySnapshot>{
        'chest': MuscleRecoverySnapshot(
          muscleCode: 'chest',
          displayName: '대흉근',
          muscleSize: MuscleSize.large,
          lastWorkedAt: DateTime(2026, 3, 1, 10, 30),
        ),
      };

      await service.saveSnapshot(
        heatmapEntries: entries,
        workoutLogs: logs,
        recoveryByCode: recovery,
      );

      final restored = await service.readSnapshot();
      expect(restored, isNotNull);
      expect(restored!.heatmapEntries.length, 1);
      expect(restored.heatmapEntries.first.muscleCode, 'chest');
      expect(restored.workoutLogs.length, 1);
      expect(restored.workoutLogs.first.exerciseName, '벤치프레스');
      expect(restored.recoveryByCode.containsKey('chest'), isTrue);
    });

    test('운동 기록 draft 오프라인 큐 저장/복구', () async {
      final draft = WorkoutLogDraft(
        exerciseId: 'squat',
        sets: 5,
        reps: 5,
        weightKg: 100,
        performedAt: DateTime(2026, 3, 1, 20, 0),
      );

      await service.enqueueWorkoutDraft(draft);
      final queue = await service.readWorkoutQueue();

      expect(queue.length, 1);
      expect(queue.first.draft.exerciseId, 'squat');
      expect(queue.first.draft.sets, 5);
      expect(queue.first.draft.reps, 5);
      expect(queue.first.id, isNotEmpty);
    });
  });
}
