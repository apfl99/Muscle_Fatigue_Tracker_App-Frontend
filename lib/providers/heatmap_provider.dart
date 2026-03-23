import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../services/offline_sync_cache_service.dart';
import '../services/supabase_service.dart';

@immutable
class NextWorkoutSuggestion {
  const NextWorkoutSuggestion({
    required this.targetMuscleCode,
    required this.overloadedMuscleCodes,
    required this.strategy,
    required this.confidence,
  });

  static const fallback = NextWorkoutSuggestion(
    targetMuscleCode: 'latissimus',
    overloadedMuscleCodes: <String>[],
    strategy: 'balanced_recovery',
    confidence: 0.35,
  );

  final String targetMuscleCode;
  final List<String> overloadedMuscleCodes;
  final String strategy;
  final double confidence;

  bool get hasRecoverySignals => overloadedMuscleCodes.isNotEmpty;
}

class HeatmapProvider extends ChangeNotifier {
  HeatmapProvider({
    SupabaseService? supabaseService,
    OfflineSyncCacheService? offlineCacheService,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _offlineCacheService = offlineCacheService ?? OfflineSyncCacheService();

  final SupabaseService _supabaseService;
  final OfflineSyncCacheService _offlineCacheService;

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
  bool _lastSaveQueuedOffline = false;

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
  bool get lastSaveQueuedOffline => _lastSaveQueuedOffline;
  int get todayWorkoutVolume => _workoutVolumeForDate(DateTime.now());
  int get yesterdayWorkoutVolume => _workoutVolumeForDate(
        DateTime.now().subtract(const Duration(days: 1)),
      );
  int get performanceScore {
    if (_heatmapEntries.isEmpty) {
      return 0;
    }
    final total = _heatmapEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.conditionDisplayScore,
    );
    return (total / _heatmapEntries.length).round().clamp(0, 100);
  }

  NextWorkoutSuggestion get nextWorkoutSuggestion =>
      _buildNextWorkoutSuggestion();

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
      await _syncQueuedWorkoutLogs();
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
      await _offlineCacheService.saveSnapshot(
        heatmapEntries: _heatmapEntries,
        workoutLogs: _workoutLogs,
        recoveryByCode: _muscleRecoveryByCode,
      );
    } on AuthException catch (error) {
      if (_isLikelyNetworkError(error) &&
          await _restoreFromOfflineCache(
            message: 'offline.cachedMode',
          )) {
        // 캐시 복구 성공 시 인증 에러 메시지를 대체한다.
      } else {
        _errorMessage = 'errors.sessionRequired';
      }
    } on PostgrestException catch (error) {
      if (_isLikelyNetworkError(error) &&
          await _restoreFromOfflineCache(
            message: 'offline.cachedMode',
          )) {
        // 캐시 복구 성공 시 네트워크 오류 메시지를 대체한다.
      } else {
        _errorMessage = _mapPostgrestError(error);
      }
    } catch (error) {
      if (_isLikelyNetworkError(error) &&
          await _restoreFromOfflineCache(
            message: 'offline.cachedMode',
          )) {
        // 캐시 복구 성공 시 네트워크 오류 메시지를 대체한다.
      } else {
        _errorMessage = 'errors.dataLoadFailed';
      }
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
      _searchErrorMessage = 'errors.sessionExpired';
    } on PostgrestException catch (error) {
      _searchErrorMessage = _mapPostgrestError(error);
    } catch (error) {
      _searchErrorMessage = 'errors.searchFailed';
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
    _lastSaveQueuedOffline = false;
    notifyListeners();

    try {
      await _supabaseService.insertWorkoutLog(draft: draft);
      _logFunnelEvent(
        'on_log_saved_success',
        params: {'exercise_id': draft.exerciseId},
      );
      await refreshAll();
      return true;
    } on AuthException catch (error) {
      if (_isLikelyNetworkError(error)) {
        await _queueWorkoutLogOffline(draft);
        return true;
      }
      _errorMessage = 'errors.sessionExpired';
      return false;
    } on PostgrestException catch (error) {
      if (_isLikelyNetworkError(error)) {
        await _queueWorkoutLogOffline(draft);
        return true;
      }
      _errorMessage = _mapPostgrestError(error);
      return false;
    } catch (error) {
      if (_isLikelyNetworkError(error)) {
        await _queueWorkoutLogOffline(draft);
        return true;
      }
      _errorMessage = 'errors.saveWorkoutFailed';
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
      return 'errors.permissionDenied';
    }
    if (code == '401' || code == 'PGRST301') {
      return 'errors.sessionExpired';
    }

    final message = error.message.trim();
    final lowered = message.toLowerCase();
    final details = '${error.details ?? ''}'.toLowerCase();
    if (lowered.contains('cardio logs require duration_minutes') ||
        details.contains('cardio logs require duration_minutes')) {
      return 'errors.cardioDurationRequired';
    }
    if (lowered.contains('weight logs require sets and reps') ||
        details.contains('weight logs require sets and reps')) {
      return 'errors.weightSetRepRequired';
    }
    if (message.isNotEmpty) {
      return message;
    }

    return 'errors.serverRequestFailed';
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

  Future<void> _queueWorkoutLogOffline(WorkoutLogDraft draft) async {
    await _offlineCacheService.enqueueWorkoutDraft(draft);
    _lastSaveQueuedOffline = true;
    _errorMessage = null;
    _logFunnelEvent(
      'on_log_saved_offline_queued',
      params: {'exercise_id': draft.exerciseId},
    );
  }

  Future<void> _syncQueuedWorkoutLogs() async {
    final queue = await _offlineCacheService.readWorkoutQueue();
    if (queue.isEmpty) {
      return;
    }

    final remaining = <QueuedWorkoutDraft>[];
    var uploaded = 0;
    for (var index = 0; index < queue.length; index += 1) {
      final queued = queue[index];
      try {
        await _supabaseService.insertWorkoutLog(draft: queued.draft);
        uploaded += 1;
      } catch (error) {
        if (_isLikelyNetworkError(error)) {
          remaining.addAll(queue.sublist(index));
          break;
        }
        // 검증/권한 오류는 손실 방지를 위해 큐에 남겨 재검토 가능하게 둔다.
        remaining.add(queued);
      }
    }

    await _offlineCacheService.replaceWorkoutQueue(remaining);
    if (uploaded > 0) {
      _logFunnelEvent(
        'on_offline_queue_synced',
        params: {
          'uploaded_count': uploaded,
          'remaining_count': remaining.length,
        },
      );
    }
  }

  Future<bool> _restoreFromOfflineCache({required String message}) async {
    final snapshot = await _offlineCacheService.readSnapshot();
    if (snapshot == null) {
      return false;
    }
    _heatmapEntries = snapshot.heatmapEntries;
    _workoutLogs = snapshot.workoutLogs;
    _muscleRecoveryByCode = snapshot.recoveryByCode;
    _lastSyncedAt = snapshot.savedAt;
    _errorMessage = message;
    return true;
  }

  bool _isLikelyNetworkError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is PostgrestException) {
      final text =
          '${error.message} ${error.details ?? ''}'.trim().toLowerCase();
      return text.contains('failed host lookup') ||
          text.contains('network') ||
          text.contains('socket') ||
          text.contains('connection') ||
          text.contains('timeout');
    }
    final lowered = error.toString().toLowerCase();
    return lowered.contains('socketexception') ||
        lowered.contains('failed host lookup') ||
        lowered.contains('network') ||
        lowered.contains('connection') ||
        lowered.contains('timeout');
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

  NextWorkoutSuggestion _buildNextWorkoutSuggestion() {
    final yesterdayMuscleLoad = _buildYesterdayMuscleLoad();
    if (yesterdayMuscleLoad.isEmpty) {
      final fallbackTarget = _firstGreenMuscle() ??
          NextWorkoutSuggestion.fallback.targetMuscleCode;
      return NextWorkoutSuggestion(
        targetMuscleCode: fallbackTarget,
        overloadedMuscleCodes: const [],
        strategy: NextWorkoutSuggestion.fallback.strategy,
        confidence: NextWorkoutSuggestion.fallback.confidence,
      );
    }

    final sortedLoads = yesterdayMuscleLoad.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final overloadedCodes = sortedLoads
        .take(3)
        .map((entry) => entry.key)
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    final dominantGroup = _resolveDominantGroup(sortedLoads.first.key);
    final strategy = _strategyForGroup(dominantGroup);
    final candidateTargets = _candidateTargetsForGroup(dominantGroup);
    final targetCode = _pickTargetMuscleCode(
      candidates: candidateTargets,
      overloadedMuscles: overloadedCodes,
    );

    final topLoad = sortedLoads.first.value;
    final secondLoad = sortedLoads.length > 1 ? sortedLoads[1].value : 0.0;
    final spread = topLoad <= 0 ? 0.0 : ((topLoad - secondLoad) / topLoad);
    final confidence = (0.55 + spread * 0.35).clamp(0.45, 0.95);

    return NextWorkoutSuggestion(
      targetMuscleCode: targetCode,
      overloadedMuscleCodes: overloadedCodes,
      strategy: strategy,
      confidence: confidence,
    );
  }

  Map<String, double> _buildYesterdayMuscleLoad() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final yesterdayLogs = _workoutLogs.where((log) {
      return !log.performedAt.isBefore(startOfYesterday) &&
          log.performedAt.isBefore(startOfToday);
    });

    final loadByMuscle = <String, double>{};
    for (final log in yesterdayLogs) {
      final volume = _volumeScorePerLog(log);
      final primary = log.primaryMuscles.map(_normalizeMuscleCode);
      final secondary = log.secondaryMuscles.map(_normalizeMuscleCode);
      for (final code in primary) {
        if (code.isEmpty) {
          continue;
        }
        loadByMuscle[code] = (loadByMuscle[code] ?? 0) + volume;
      }
      for (final code in secondary) {
        if (code.isEmpty) {
          continue;
        }
        loadByMuscle[code] = (loadByMuscle[code] ?? 0) + volume * 0.58;
      }
    }

    if (loadByMuscle.isNotEmpty) {
      return loadByMuscle;
    }

    for (final entry in _heatmapEntries) {
      if (entry.status != HeatmapStatus.red) {
        continue;
      }
      final code = _normalizeMuscleCode(entry.muscleCode);
      if (code.isEmpty) {
        continue;
      }
      final severity = entry.conditionScore > 0 ? entry.conditionScore : 1.8;
      loadByMuscle[code] = (loadByMuscle[code] ?? 0) + severity;
    }
    return loadByMuscle;
  }

  double _volumeScorePerLog(WorkoutLogRecord log) {
    final hasWeightVolume =
        (log.sets ?? 0) > 0 && (log.reps ?? 0) > 0 && (log.weightKg ?? 0) > 0;
    if (hasWeightVolume) {
      final sets = (log.sets ?? 1).clamp(1, 20);
      final reps = (log.reps ?? 1).clamp(1, 50);
      final weight = (log.weightKg ?? 1).clamp(1, 400);
      return sets * reps * (weight / 10.0);
    }

    final hasBodyweightVolume = (log.sets ?? 0) > 0 && (log.reps ?? 0) > 0;
    if (hasBodyweightVolume) {
      final sets = (log.sets ?? 1).clamp(1, 20);
      final reps = (log.reps ?? 1).clamp(1, 60);
      return sets * reps * 0.8;
    }

    if ((log.durationMinutes ?? 0) > 0 || (log.distanceKm ?? 0) > 0) {
      final minutes = (log.durationMinutes ?? 0).clamp(0, 240);
      final distance = ((log.distanceKm ?? 0) * 30).clamp(0, 600);
      return (minutes * 1.3) + distance;
    }

    return 12.0;
  }

  String _resolveDominantGroup(String muscleCode) {
    return _muscleGroupByCode[_normalizeMuscleCode(muscleCode)] ?? 'upper_push';
  }

  String _strategyForGroup(String dominantGroup) {
    return switch (dominantGroup) {
      'upper_push' => 'push_to_pull',
      'upper_pull' => 'pull_to_lower',
      'lower' => 'lower_to_upper',
      'core' => 'core_to_lower',
      _ => 'balanced_recovery',
    };
  }

  List<String> _candidateTargetsForGroup(String dominantGroup) {
    return switch (dominantGroup) {
      'upper_push' => const ['latissimus', 'trapezius', 'hamstrings', 'glutes'],
      'upper_pull' => const ['quadriceps', 'glutes', 'calves'],
      'lower' => const ['chest', 'front_deltoid', 'latissimus'],
      'core' => const ['glutes', 'quadriceps', 'latissimus'],
      _ => const ['latissimus', 'quadriceps', 'chest'],
    };
  }

  String _pickTargetMuscleCode({
    required List<String> candidates,
    required List<String> overloadedMuscles,
  }) {
    final overloadedSet = overloadedMuscles.toSet();
    final byCode = heatmapEntryByMuscleCode;

    for (final code in candidates) {
      if (overloadedSet.contains(code)) {
        continue;
      }
      final status = byCode[code]?.status ?? HeatmapStatus.green;
      if (status == HeatmapStatus.green) {
        return code;
      }
    }
    for (final code in candidates) {
      if (!overloadedSet.contains(code)) {
        return code;
      }
    }
    if (candidates.isNotEmpty) {
      return _firstGreenMuscle() ?? candidates.first;
    }
    return _firstGreenMuscle() ?? 'latissimus';
  }

  String? _firstGreenMuscle() {
    for (final entry in _heatmapEntries) {
      if (entry.status == HeatmapStatus.green) {
        final normalized = _normalizeMuscleCode(entry.muscleCode);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    return null;
  }

  int _workoutVolumeForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    var volume = 0.0;
    for (final log in _workoutLogs) {
      if (log.performedAt.isBefore(start) || !log.performedAt.isBefore(end)) {
        continue;
      }
      volume += _volumeScorePerLog(log);
    }
    return volume.round().clamp(0, 99999);
  }

  static const Map<String, String> _muscleGroupByCode = {
    'chest': 'upper_push',
    'pectoralis_major': 'upper_push',
    'front_deltoid': 'upper_push',
    'anterior_deltoid': 'upper_push',
    'triceps': 'upper_push',
    'biceps': 'upper_pull',
    'forearms': 'upper_pull',
    'forearm_flexor': 'upper_pull',
    'forearm_extensor': 'upper_pull',
    'brachioradialis': 'upper_pull',
    'latissimus': 'upper_pull',
    'latissimus_upper': 'upper_pull',
    'latissimus_lower': 'upper_pull',
    'trapezius': 'upper_pull',
    'rear_deltoid': 'upper_pull',
    'erector_spinae': 'upper_pull',
    'lower_back': 'upper_pull',
    'quadriceps': 'lower',
    'hamstrings': 'lower',
    'glutes': 'lower',
    'calves': 'lower',
    'rectus_abdominis': 'core',
    'obliques': 'core',
  };

  String _normalizeMuscleCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) {
      return normalized;
    }
    return switch (normalized) {
      'front_delts' || 'anterior_deltoid' => 'front_deltoid',
      'lateral_delts' || 'side_deltoid' => 'lateral_deltoid',
      'rear_delts' || 'posterior_deltoid' => 'rear_deltoid',
      'quads' => 'quadriceps',
      'lats' || 'latissimus_dorsi' => 'latissimus',
      'abs' || 'abdominals' => 'rectus_abdominis',
      'pecs' || 'pectoralis_major' => 'chest',
      'gastrocnemius_medial' || 'gastrocnemius_lateral' => 'gastrocnemius',
      'spinal_erectors' || 'erectors' => 'erector_spinae',
      'lumbar' => 'lower_back',
      'wrist_flexor' => 'forearms',
      'wrist_extensor' => 'forearms',
      'forearm' || 'forearms' => 'forearms',
      'forearm_flexor' || 'forearm_extensor' => 'forearms',
      'brachioradialis' => 'forearms',
      'biceps_brachii' => 'biceps',
      _ => normalized,
    };
  }
}
