import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../services/supabase_service.dart';

class HeatmapProvider extends ChangeNotifier {
  HeatmapProvider({
    SupabaseService? supabaseService,
  }) : _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseService _supabaseService;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSearching = false;

  String? _errorMessage;
  String? _searchErrorMessage;

  DateTime? _lastSyncedAt;

  List<MuscleHeatmapEntry> _heatmapEntries = const [];
  List<WorkoutLogRecord> _workoutLogs = const [];
  List<ExerciseSuggestion> _exerciseSuggestions = const [];
  Map<String, MuscleRecoverySnapshot> _muscleRecoveryByCode = const {};

  Timer? _searchDebounce;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  String? get searchErrorMessage => _searchErrorMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  List<MuscleHeatmapEntry> get heatmapEntries => _heatmapEntries;
  List<WorkoutLogRecord> get workoutLogs => _workoutLogs;
  List<ExerciseSuggestion> get exerciseSuggestions => _exerciseSuggestions;
  Map<String, MuscleRecoverySnapshot> get muscleRecoveryByCode =>
      _muscleRecoveryByCode;
  Map<String, MuscleHeatmapEntry> get heatmapEntryByMuscleCode {
    final mapped = <String, MuscleHeatmapEntry>{};
    for (final entry in _heatmapEntries) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      final previous = mapped[code];
      if (previous == null ||
          _heatmapPriority(entry.status) > _heatmapPriority(previous.status)) {
        mapped[code] = entry;
      }
    }
    return mapped;
  }

  int get streakDays {
    if (_workoutLogs.isEmpty) {
      return 0;
    }

    final normalizedDays = _workoutLogs
        .map(
          (entry) => DateTime(
            entry.performedAt.year,
            entry.performedAt.month,
            entry.performedAt.day,
          ),
        )
        .toSet();

    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    var streak = 0;

    while (normalizedDays.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  HeatmapStatus get dominantStatus {
    if (_heatmapEntries.any((entry) => entry.status == HeatmapStatus.red)) {
      return HeatmapStatus.red;
    }
    if (_heatmapEntries.any((entry) => entry.status == HeatmapStatus.yellow)) {
      return HeatmapStatus.yellow;
    }
    if (_heatmapEntries.any((entry) => entry.status == HeatmapStatus.green)) {
      return HeatmapStatus.green;
    }
    return HeatmapStatus.unknown;
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await refreshAll();
    _isInitialized = true;
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final recoveryFuture = _supabaseService
          .fetchMuscleRecoverySnapshots()
          .catchError((_) => <MuscleRecoverySnapshot>[]);
      final results = await Future.wait<dynamic>([
        _supabaseService.getMuscleHeatmapStatus(),
        _supabaseService.fetchWorkoutLogs(),
        recoveryFuture,
      ]);

      _heatmapEntries = results[0] as List<MuscleHeatmapEntry>;
      _workoutLogs = results[1] as List<WorkoutLogRecord>;
      final snapshots = results[2] as List<MuscleRecoverySnapshot>;
      _muscleRecoveryByCode = <String, MuscleRecoverySnapshot>{
        for (final snapshot in snapshots) snapshot.muscleCode: snapshot,
      };
      _lastSyncedAt = DateTime.now();
    } on AuthException {
      _errorMessage = '로그인 세션이 필요합니다. 다시 로그인해 주세요.';
    } on PostgrestException catch (error) {
      _errorMessage = _mapPostgrestError(error);
    } catch (error) {
      _errorMessage = '데이터를 불러오는 중 오류가 발생했습니다: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void onSearchKeywordChanged(String keyword) {
    _searchDebounce?.cancel();
    if (keyword.trim().isEmpty) {
      _exerciseSuggestions = const [];
      _searchErrorMessage = null;
      notifyListeners();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      await searchExercises(keyword);
    });
  }

  Future<void> searchExercises(String keyword) async {
    if (keyword.trim().isEmpty) {
      _exerciseSuggestions = const [];
      _searchErrorMessage = null;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchErrorMessage = null;
    notifyListeners();

    try {
      final results = await _supabaseService.searchExercises(keyword: keyword);
      _exerciseSuggestions = results;
      _logFunnelEvent(
        'on_exercise_searched',
        params: {
          'keyword_length': keyword.length,
          'result_count': results.length,
        },
      );
    } on AuthException {
      _searchErrorMessage = '로그인 세션이 만료되었습니다. 다시 로그인해 주세요.';
    } on PostgrestException catch (error) {
      _searchErrorMessage = _mapPostgrestError(error);
    } catch (error) {
      _searchErrorMessage = '운동 검색에 실패했습니다: $error';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<bool> saveWorkoutLog({
    required WorkoutLogDraft draft,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabaseService.insertWorkoutLog(draft: draft);
      _logFunnelEvent(
        'on_log_saved_success',
        params: {'exercise_id': draft.exerciseId},
      );
      await refreshAll();
      return true;
    } on AuthException {
      _errorMessage = '로그인 세션이 만료되었습니다. 다시 로그인해 주세요.';
      return false;
    } on PostgrestException catch (error) {
      _errorMessage = _mapPostgrestError(error);
      return false;
    } catch (error) {
      _errorMessage = '운동 기록 저장에 실패했습니다: $error';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearSearchState() {
    _searchDebounce?.cancel();
    _exerciseSuggestions = const [];
    _searchErrorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _mapPostgrestError(PostgrestException error) {
    final code = error.code?.trim();
    if (code == '42501') {
      return '권한 오류(403): 사용자 식별값 전달 로직을 확인해 주세요.';
    }
    if (code == '401' || code == 'PGRST301') {
      return '인증이 만료되었습니다. 다시 로그인해 주세요.';
    }

    final message = error.message.trim();
    final lowered = message.toLowerCase();
    final details = '${error.details ?? ''}'.toLowerCase();
    if (lowered.contains('cardio logs require duration_minutes') ||
        details.contains('cardio logs require duration_minutes')) {
      return '유산소 기록은 운동 시간(분)을 반드시 입력해야 합니다.';
    }
    if (lowered.contains('weight logs require sets and reps') ||
        details.contains('weight logs require sets and reps')) {
      return '무산소 기록은 세트 수와 횟수를 반드시 입력해야 합니다.';
    }
    if (message.isNotEmpty) {
      return message;
    }

    return '서버 요청 처리 중 오류가 발생했습니다.';
  }

  MuscleRecoverySnapshot? getRecoverySnapshot(String muscleCode) {
    return _muscleRecoveryByCode[muscleCode.trim().toLowerCase()];
  }

  int estimateRecoveryHours({
    required String muscleCode,
    required HeatmapStatus status,
  }) {
    final snapshot = getRecoverySnapshot(muscleCode);
    final muscleSize = snapshot?.muscleSize ?? MuscleSize.unknown;
    switch (muscleSize) {
      case MuscleSize.large:
        if (status == HeatmapStatus.red) return 72;
        if (status == HeatmapStatus.yellow) return 48;
        return 24;
      case MuscleSize.small:
        if (status == HeatmapStatus.red) return 48;
        if (status == HeatmapStatus.yellow) return 24;
        return 12;
      case MuscleSize.unknown:
        if (status == HeatmapStatus.red) return 60;
        if (status == HeatmapStatus.yellow) return 36;
        return 18;
    }
  }

  void _logFunnelEvent(String name, {Map<String, Object?>? params}) {
    debugPrint('[funnel] $name ${params ?? const {}}');
  }

  int _heatmapPriority(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return 4;
      case HeatmapStatus.yellow:
        return 3;
      case HeatmapStatus.green:
        return 2;
      case HeatmapStatus.unknown:
        return 1;
    }
  }

  String _normalizeMuscleCode(String code) {
    final normalized = code.trim().toLowerCase();
    return switch (normalized) {
      'front_delts' => 'front_deltoid',
      'lateral_delts' => 'lateral_deltoid',
      'rear_delts' => 'rear_deltoid',
      'quads' => 'quadriceps',
      'lats' || 'latissimus_dorsi' => 'latissimus',
      'abs' || 'abdominals' => 'rectus_abdominis',
      'gastrocnemius' || 'soleus' => 'calves',
      _ => normalized,
    };
  }
}
