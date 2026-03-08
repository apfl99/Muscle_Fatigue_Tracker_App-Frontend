import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/heatmap_api_client.dart';
import '../data/heatmap_repository.dart';
import '../model/heatmap_models.dart';

class HeatmapSyncHook extends ChangeNotifier {
  HeatmapSyncHook({
    required HeatmapRepositoryContract repository,
    Duration searchDebounce = const Duration(milliseconds: 350),
  })  : _repository = repository,
        _searchDebounce = searchDebounce;

  final HeatmapRepositoryContract _repository;
  final Duration _searchDebounce;

  bool _isLoading = false;
  bool _isMutating = false;
  bool _isSearchLoading = false;
  String? _errorMessage;
  String? _searchErrorMessage;
  DateTime? _lastSyncedAt;
  List<MuscleHeatmapEntry> _entries = const [];
  List<ExerciseSuggestion> _suggestions = const [];
  String _currentKeyword = '';
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  bool get isSearchLoading => _isSearchLoading;
  String? get errorMessage => _errorMessage;
  String? get searchErrorMessage => _searchErrorMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  List<MuscleHeatmapEntry> get entries => _entries;
  List<ExerciseSuggestion> get suggestions => _suggestions;
  String get currentKeyword => _currentKeyword;

  Map<String, HeatmapStatus> get statusByMuscleCode => {
        for (final entry in _entries) entry.muscleCode: entry.status,
      };

  Future<void> initialize() async {
    await refreshHeatmap();
  }

  Future<void> refreshHeatmap({bool silent = false}) async {
    if (_isLoading) {
      return;
    }

    _isLoading = !silent;
    _errorMessage = null;
    notifyListeners();

    try {
      _entries = await _repository.fetchHeatmapStatus();
      _lastSyncedAt = DateTime.now();
    } on HeatmapApiException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void onSearchKeywordChanged(String rawKeyword) {
    _currentKeyword = rawKeyword;
    _searchErrorMessage = null;
    _debounceTimer?.cancel();

    if (rawKeyword.trim().isEmpty) {
      _suggestions = const [];
      _isSearchLoading = false;
      notifyListeners();
      return;
    }

    _isSearchLoading = true;
    notifyListeners();

    final thisSearchGeneration = ++_searchGeneration;
    _debounceTimer = Timer(_searchDebounce, () async {
      await _runSearch(
        keyword: rawKeyword,
        searchGeneration: thisSearchGeneration,
      );
    });
  }

  Future<void> _runSearch({
    required String keyword,
    required int searchGeneration,
  }) async {
    try {
      final result = await _repository.searchExercises(keyword);
      if (searchGeneration != _searchGeneration) {
        return;
      }

      _suggestions = result;
      _searchErrorMessage = null;
    } on HeatmapApiException catch (error) {
      if (searchGeneration != _searchGeneration) {
        return;
      }
      _suggestions = const [];
      _searchErrorMessage = error.message;
    } catch (error) {
      if (searchGeneration != _searchGeneration) {
        return;
      }
      _suggestions = const [];
      _searchErrorMessage = error.toString();
    } finally {
      if (searchGeneration == _searchGeneration) {
        _isSearchLoading = false;
        notifyListeners();
      }
    }
  }

  void clearSearchState() {
    _debounceTimer?.cancel();
    _currentKeyword = '';
    _suggestions = const [];
    _isSearchLoading = false;
    _searchErrorMessage = null;
    notifyListeners();
  }

  Future<bool> recordWorkout({
    required WorkoutLogDraft draft,
  }) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.insertWorkoutLog(draft);
      clearSearchState();
      await refreshHeatmap(silent: true);
      return true;
    } on HeatmapApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
