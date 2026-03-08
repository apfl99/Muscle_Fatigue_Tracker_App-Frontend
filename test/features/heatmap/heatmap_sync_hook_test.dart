import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/data/heatmap_repository.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/hook/heatmap_sync_hook.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/model/heatmap_models.dart';

class _FakeHeatmapRepository implements HeatmapRepositoryContract {
  int fetchCount = 0;
  int insertCount = 0;
  int searchCount = 0;

  bool shouldFailInsert = false;
  WorkoutLogDraft? lastInsertDraft;

  @override
  Future<List<MuscleHeatmapEntry>> fetchHeatmapStatus() async {
    fetchCount += 1;
    if (fetchCount == 1) {
      return const [
        MuscleHeatmapEntry(
          muscleCode: 'chest',
          status: HeatmapStatus.red,
        ),
      ];
    }

    return const [
      MuscleHeatmapEntry(
        muscleCode: 'chest',
        status: HeatmapStatus.green,
      ),
    ];
  }

  @override
  Future<void> insertWorkoutLog(WorkoutLogDraft draft) async {
    insertCount += 1;
    lastInsertDraft = draft;
    if (shouldFailInsert) {
      throw Exception('insert failed');
    }
  }

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String keyword) async {
    searchCount += 1;
    if (keyword.trim().isEmpty) {
      return const [];
    }
    return const [
      ExerciseSuggestion(
        id: 'exercise-id-1',
        name: 'Back Squat',
        category: 'free_weight',
        exerciseType: ExerciseType.weight,
        muscleSize: MuscleSize.large,
      ),
    ];
  }

  @override
  void dispose() {}
}

void main() {
  group('HeatmapSyncHook', () {
    test('initialize 시 히트맵 데이터를 조회한다', () async {
      final repository = _FakeHeatmapRepository();
      final hook = HeatmapSyncHook(repository: repository);

      await hook.initialize();

      expect(repository.fetchCount, 1);
      expect(hook.entries.length, 1);
      expect(hook.entries.first.status, HeatmapStatus.red);
      expect(hook.errorMessage, isNull);

      hook.dispose();
    });

    test('운동 저장 성공 시 히트맵을 재조회한다 (invalidate 동작)', () async {
      final repository = _FakeHeatmapRepository();
      final hook = HeatmapSyncHook(repository: repository);

      await hook.initialize();
      final success = await hook.recordWorkout(
        draft: const WorkoutLogDraft(exerciseId: 'exercise-id-1'),
      );

      expect(success, isTrue);
      expect(repository.insertCount, 1);
      expect(repository.fetchCount, 2);
      expect(hook.entries.first.status, HeatmapStatus.green);
      expect(hook.errorMessage, isNull);

      hook.dispose();
    });

    test('검색 입력은 debounce 이후 1회만 호출된다', () async {
      final repository = _FakeHeatmapRepository();
      final hook = HeatmapSyncHook(
        repository: repository,
        searchDebounce: const Duration(milliseconds: 250),
      );

      hook.onSearchKeywordChanged('스');
      hook.onSearchKeywordChanged('스쿼');
      hook.onSearchKeywordChanged('스쿼트');

      await Future<void>.delayed(const Duration(milliseconds: 320));

      expect(repository.searchCount, 1);
      expect(hook.suggestions.length, 1);
      expect(hook.suggestions.first.name, 'Back Squat');

      hook.dispose();
    });
  });
}
