import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muscle_fatigue_tracker/features/heatmap/model/heatmap_models.dart';
import 'package:muscle_fatigue_tracker/main.dart' show SensorDataPage;
import 'package:muscle_fatigue_tracker/providers/heatmap_provider.dart';
import 'package:muscle_fatigue_tracker/screens/heatmap_full_viewer_page.dart';
import 'package:muscle_fatigue_tracker/screens/main_home_page.dart';
import 'package:muscle_fatigue_tracker/screens/measurement_history_page.dart';
import 'package:muscle_fatigue_tracker/screens/splash_screen.dart';
import 'package:muscle_fatigue_tracker/services/supabase_service.dart';
import 'package:muscle_fatigue_tracker/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '앱 실행 -> 스플래시 스킵 -> 메인 진입 -> 뷰어 배경 변화 -> 화면 왕복 -> 히스토리 달력 필터',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'v2_onboarding_seen': true,
      });

      final fakeService = _FakeSupabaseService();
      final fakeAdController = _FakeSplashAdController(
        readyAfter: const Duration(milliseconds: 10),
      );
      late HeatmapProvider provider;

      await tester.pumpWidget(
        ChangeNotifierProvider<HeatmapProvider>(
          create: (_) {
            provider = HeatmapProvider(supabaseService: fakeService);
            return provider;
          },
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            home: SplashScreen(
              adLoadTimeout: const Duration(milliseconds: 350),
              adController: fakeAdController,
              homeBuilder: (_) => const MainHomePage(),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(MainHomePage), findsOneWidget);
      expect(fakeAdController.showCount, 1);

      await tester.tap(find.byKey(const Key('main_home_fab')));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.enterText(
        find.byKey(const Key('workout_search_field')),
        '스쿼트',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('exercise_suggestion_ex-squat')));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.enterText(find.byType(TextField).at(1), '25');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('workout_log_save_button')));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(provider.dominantStatus, HeatmapStatus.red);

      await tester.tap(find.byKey(const Key('hero_preview_card')));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(HeatmapFullViewerPage), findsOneWidget);
      expect(
        find.byKey(const Key('viewer_dynamic_background')),
        findsOneWidget,
      );

      final stubTapArea = find.byKey(const Key('e2e_stub_muscle_map'));
      if (stubTapArea.evaluate().isNotEmpty) {
        await tester.tap(stubTapArea);
      } else {
        await tester.tap(find.text('가슴 (대근육)'));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      final hasBottomSheet = find
          .byKey(const Key('muscle_performance_sheet'))
          .evaluate()
          .isNotEmpty;
      final hasSnackBar = find.byType(SnackBar).evaluate().isNotEmpty;
      expect(hasBottomSheet || hasSnackBar, isTrue);
      if (hasBottomSheet) {
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }

      await tester.tap(find.byKey(const Key('go_sensor_analysis_button')));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(SensorDataPage), findsOneWidget);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 1200));

      await tester.tap(find.byIcon(Icons.history).first);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(MeasurementHistoryPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('history_mode_calendar')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byKey(const Key('history_select_today')));
      await tester.pump(const Duration(milliseconds: 700));

      final filterText = tester.widget<Text>(
        find.byKey(const Key('history_filter_label')),
      );
      expect(filterText.data, contains('선택'));
    },
  );

  testWidgets('스플래시 이후 메인으로 진입', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'v2_onboarding_seen': true,
    });

    final fakeService = _FakeSupabaseService();
    final fakeAdController = _FakeSplashAdController(readyAfter: Duration.zero);

    await tester.pumpWidget(
      ChangeNotifierProvider<HeatmapProvider>(
        create: (_) => HeatmapProvider(supabaseService: fakeService),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: SplashScreen(
            adLoadTimeout: const Duration(seconds: 1),
            adController: fakeAdController,
            homeBuilder: (_) => const MainHomePage(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fakeAdController.showCount, 1);
    expect(find.byType(MainHomePage), findsOneWidget);
  });
}

class _FakeSplashAdController implements SplashAdController {
  _FakeSplashAdController({required this.readyAfter});

  final Duration readyAfter;
  bool _ready = false;
  int showCount = 0;

  @override
  Future<void> initialize() async {
    if (readyAfter > Duration.zero) {
      await Future<void>.delayed(readyAfter);
    }
    _ready = true;
  }

  @override
  bool get isInterstitialReady => _ready;

  @override
  void loadInterstitial() {}

  @override
  void showInterstitial({required VoidCallback onClosed}) {
    showCount += 1;
    onClosed();
  }
}

class _FakeSupabaseService extends SupabaseService {
  bool _saved = false;
  final List<WorkoutLogRecord> _records = <WorkoutLogRecord>[];

  @override
  Future<List<MuscleHeatmapEntry>> getMuscleHeatmapStatus() async {
    if (_saved) {
      return const <MuscleHeatmapEntry>[
        MuscleHeatmapEntry(muscleCode: 'chest', status: HeatmapStatus.red),
        MuscleHeatmapEntry(
          muscleCode: 'quadriceps',
          status: HeatmapStatus.yellow,
        ),
      ];
    }
    return const <MuscleHeatmapEntry>[
      MuscleHeatmapEntry(muscleCode: 'chest', status: HeatmapStatus.green),
    ];
  }

  @override
  Future<List<ExerciseSuggestion>> searchExercises({
    required String keyword,
  }) async {
    if (keyword.trim().isEmpty) {
      return const <ExerciseSuggestion>[];
    }

    return const <ExerciseSuggestion>[
      ExerciseSuggestion(
        id: 'ex-squat',
        name: '스쿼트',
        category: 'lower_body',
        exerciseType: ExerciseType.cardio,
        muscleSize: MuscleSize.large,
      ),
    ];
  }

  @override
  Future<void> insertWorkoutLog({required WorkoutLogDraft draft}) async {
    _saved = true;
    _records.insert(
      0,
      WorkoutLogRecord(
        id: 'log-1',
        exerciseId: draft.exerciseId,
        exerciseName: '스쿼트',
        category: 'lower_body',
        exerciseType: ExerciseType.cardio,
        muscleSize: MuscleSize.large,
        performedAt: DateTime.now(),
        sets: draft.sets,
        reps: draft.reps,
        weightKg: draft.weightKg,
        durationMinutes: draft.durationMinutes,
        distanceKm: draft.distanceKm,
        note: draft.note,
      ),
    );
  }

  @override
  Future<List<WorkoutLogRecord>> fetchWorkoutLogs({int limit = 30}) async {
    return _records.take(limit).toList();
  }

  @override
  Future<List<MuscleRecoverySnapshot>> fetchMuscleRecoverySnapshots({
    int limit = 120,
  }) async {
    return <MuscleRecoverySnapshot>[
      MuscleRecoverySnapshot(
        muscleCode: 'chest',
        displayName: '가슴',
        muscleSize: MuscleSize.large,
        lastWorkedAt: DateTime.now(),
      ),
    ];
  }
}
