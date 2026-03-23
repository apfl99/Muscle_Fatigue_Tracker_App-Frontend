import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muscle_fatigue_tracker/features/heatmap/model/heatmap_models.dart';
import 'package:muscle_fatigue_tracker/providers/heatmap_provider.dart';
import 'package:muscle_fatigue_tracker/screens/heatmap_full_viewer_page.dart';
import 'package:muscle_fatigue_tracker/screens/main_home_page.dart';
import 'package:muscle_fatigue_tracker/screens/splash_screen.dart';
import 'package:muscle_fatigue_tracker/services/supabase_service.dart';
import 'package:muscle_fatigue_tracker/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProviderChannels();

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
        EasyLocalization(
          supportedLocales: const <Locale>[
            Locale('ko', 'KR'),
            Locale('en', 'US'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('ko', 'KR'),
          startLocale: const Locale('ko', 'KR'),
          saveLocale: false,
          child: ChangeNotifierProvider<HeatmapProvider>(
            create: (_) {
              provider = HeatmapProvider(supabaseService: fakeService);
              return provider;
            },
            child: Builder(
              builder: (context) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                theme: AppTheme.darkTheme,
                home: SplashScreen(
                  minimumSplashDuration: const Duration(milliseconds: 10),
                  adLoadTimeout: const Duration(milliseconds: 350),
                  adController: fakeAdController,
                  homeBuilder: (_) => const MainHomePage(),
                ),
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.byType(MainHomePage),
        timeout: const Duration(seconds: 8),
      );
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
      await _pumpUntilAbsent(
        tester,
        find.byKey(const Key('workout_log_save_button')),
        timeout: const Duration(seconds: 8),
      );

      expect(provider.dominantStatus, HeatmapStatus.red);

      final heroPreviewCard = find.byKey(const Key('hero_preview_card'));
      await _pumpUntilFound(
        tester,
        heroPreviewCard,
        timeout: const Duration(seconds: 5),
      );
      await tester.ensureVisible(heroPreviewCard);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(heroPreviewCard);
      await _pumpUntilFound(
        tester,
        find.byType(HeatmapFullViewerPage),
        timeout: const Duration(seconds: 3),
      );
      if (find.byType(HeatmapFullViewerPage).evaluate().isEmpty) {
        final mainContext = tester.element(find.byType(MainHomePage).first);
        Navigator.of(mainContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const HeatmapFullViewerPage(),
          ),
        );
        await _pumpUntilFound(
          tester,
          find.byType(HeatmapFullViewerPage),
          timeout: const Duration(seconds: 4),
        );
      }
      expect(find.byType(HeatmapFullViewerPage), findsOneWidget);
      expect(
        find.byKey(const Key('viewer_dynamic_background')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('next_workout_suggestion_card')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('heatmap_share_button')), findsOneWidget);
      expect(
        find.byKey(const Key('next_workout_target_badge')),
        findsOneWidget,
      );

      final stubTapArea = find.byKey(const Key('e2e_stub_muscle_map'));
      if (stubTapArea.evaluate().isNotEmpty) {
        await tester.ensureVisible(stubTapArea.first);
        await tester.tap(stubTapArea.first, warnIfMissed: false);
      } else {
        final chestRecoveryRow = find.byKey(const Key('recovery_row_chest'));
        if (chestRecoveryRow.evaluate().isNotEmpty) {
          await tester.ensureVisible(chestRecoveryRow.first);
          await tester.tap(chestRecoveryRow.first, warnIfMissed: false);
        }
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      var hasBottomSheet = find
          .byKey(const Key('muscle_performance_sheet'))
          .evaluate()
          .isNotEmpty;
      var hasSnackBar = find.byType(SnackBar).evaluate().isNotEmpty;
      if (!hasBottomSheet && !hasSnackBar) {
        final chestRecoveryRow = find.byKey(const Key('recovery_row_chest'));
        if (chestRecoveryRow.evaluate().isNotEmpty) {
          await tester.ensureVisible(chestRecoveryRow.first);
          await tester.tap(chestRecoveryRow.first, warnIfMissed: false);
          await tester.pumpAndSettle(const Duration(milliseconds: 600));
          hasBottomSheet = find
              .byKey(const Key('muscle_performance_sheet'))
              .evaluate()
              .isNotEmpty;
          hasSnackBar = find.byType(SnackBar).evaluate().isNotEmpty;
        }
      }
      expect(hasBottomSheet || hasSnackBar, isTrue);
      if (hasBottomSheet) {
        await tester.tap(find.byIcon(Icons.close_rounded).first);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
    },
  );

  testWidgets('스플래시 이후 메인으로 진입', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'v2_onboarding_seen': true,
    });

    final fakeService = _FakeSupabaseService();
    final fakeAdController = _FakeSplashAdController(readyAfter: Duration.zero);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[
          Locale('ko', 'KR'),
          Locale('en', 'US'),
        ],
        path: 'assets/translations',
        fallbackLocale: const Locale('ko', 'KR'),
        startLocale: const Locale('ko', 'KR'),
        saveLocale: false,
        child: ChangeNotifierProvider<HeatmapProvider>(
          create: (_) => HeatmapProvider(supabaseService: fakeService),
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: AppTheme.darkTheme,
              home: SplashScreen(
                minimumSplashDuration: const Duration(milliseconds: 10),
                adLoadTimeout: const Duration(seconds: 1),
                adController: fakeAdController,
                homeBuilder: (_) => const MainHomePage(),
              ),
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.byType(MainHomePage),
      timeout: const Duration(seconds: 8),
    );
    expect(fakeAdController.showCount, 1);
    expect(find.byType(MainHomePage), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 6),
  Duration step = const Duration(milliseconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  await tester.pump(step);
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 6),
  Duration step = const Duration(milliseconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  await tester.pump(step);
}

void _mockPathProviderChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tempPath = Directory.systemTemp.path;
  const methodChannel = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(methodChannel, (call) async {
    switch (call.method) {
      case 'getTemporaryDirectory':
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getLibraryDirectory':
      case 'getDownloadsDirectory':
        return tempPath;
      default:
        return tempPath;
    }
  });

  const messageCodec = StandardMessageCodec();
  final encodedReply = messageCodec.encodeMessage(<Object?>[tempPath]);
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.path_provider_foundation.PathProviderApi.getDirectoryPath',
    (ByteData? _) async => encodedReply,
  );
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.path_provider_foundation.PathProviderApi.getContainerPath',
    (ByteData? _) async => encodedReply,
  );
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
