import '../model/heatmap_models.dart';
import 'heatmap_api_client.dart';
import 'heatmap_api_config.dart';

abstract class HeatmapRepositoryContract {
  Future<List<MuscleHeatmapEntry>> fetchHeatmapStatus();

  Future<List<ExerciseSuggestion>> searchExercises(String keyword);

  Future<void> insertWorkoutLog(WorkoutLogDraft draft);

  void dispose();
}

class HeatmapRepository implements HeatmapRepositoryContract {
  HeatmapRepository({
    required HeatmapApiConfig config,
    HeatmapApiClient? apiClient,
  })  : _config = config,
        _apiClient = apiClient ?? HeatmapApiClient();

  factory HeatmapRepository.fromEnvironment() {
    return HeatmapRepository(
      config: HeatmapApiConfig.fromEnvironment(),
    );
  }

  final HeatmapApiConfig _config;
  final HeatmapApiClient _apiClient;

  @override
  Future<List<MuscleHeatmapEntry>> fetchHeatmapStatus() async {
    _validateConfig();
    return _apiClient.fetchHeatmapStatus();
  }

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String keyword) async {
    _validateConfig();
    return _apiClient.searchExercises(keyword: keyword);
  }

  @override
  Future<void> insertWorkoutLog(WorkoutLogDraft draft) async {
    _validateConfig();
    await _apiClient.insertWorkoutLog(draft: draft);
  }

  void _validateConfig() {
    if (!_config.isConfigured) {
      throw HeatmapApiException(
        message: _config.validationError ?? 'Heatmap API 설정이 올바르지 않습니다.',
      );
    }
  }

  @override
  void dispose() {
    _apiClient.dispose();
  }
}
