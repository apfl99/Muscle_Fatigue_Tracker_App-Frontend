import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/data/heatmap_repository.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/model/heatmap_models.dart';
import 'package:muscle_fatigue_tracker/features/heatmap/ui/muscle_heatmap_page.dart';

class _FakeE2ERepository implements HeatmapRepositoryContract {
  int fetchCount = 0;
  int insertCount = 0;
  WorkoutLogDraft? insertedDraft;

  @override
  Future<List<MuscleHeatmapEntry>> fetchHeatmapStatus() async {
    fetchCount += 1;
    if (insertCount == 0) {
      return const [
        MuscleHeatmapEntry(
          muscleCode: 'chest',
          status: HeatmapStatus.green,
        ),
      ];
    }
    return const [
      MuscleHeatmapEntry(
        muscleCode: 'chest',
        status: HeatmapStatus.red,
      ),
    ];
  }

  @override
  Future<void> insertWorkoutLog(WorkoutLogDraft draft) async {
    insertCount += 1;
    insertedDraft = draft;
  }

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String keyword) async {
    if (keyword.trim().isEmpty) {
      return const [];
    }

    return const [
      ExerciseSuggestion(
        id: 'ex-001',
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('히트맵 진입 후 빠른 운동 기록 시 실시간 동기화된다', (
    tester,
  ) async {
    final fakeRepository = _FakeE2ERepository();

    await tester.pumpWidget(
      MaterialApp(
        home: MuscleHeatmapPage(
          repository: fakeRepository,
          bridgePayload: MeasurementBridgePayload(
            measuredAt: DateTime(2026, 3, 1, 10, 30),
            fatigueScore: 1.42,
            fatigueVariance: 0.18,
            peakFrequency: 5.2,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(fakeRepository.fetchCount, greaterThanOrEqualTo(1));

    await tester.tap(find.byKey(const ValueKey('open_quick_record_button')));
    await tester.pump(const Duration(milliseconds: 700));

    final searchField = find.byKey(const ValueKey('quick_record_search_field'));
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, '스쿼트');

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 350));

    final suggestion = find.byKey(const ValueKey('exercise_suggestion_ex-001'));
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('quick_record_save_button')));
    await tester.pump(const Duration(milliseconds: 900));

    expect(fakeRepository.insertCount, 1);
    expect(fakeRepository.fetchCount, greaterThanOrEqualTo(2));
    expect(
      find.byKey(const ValueKey('quick_record_search_field')),
      findsNothing,
    );
  });
}
