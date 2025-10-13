/// 앱 전역 상수
class AppConstants {
  // 측정 관련
  static const int measurementDurationSeconds = 5;
  static const int samplingRateHz = 100;
  static const int minRequiredSamples = 100;

  // 피로도 레벨
  static const double lowFatigueThreshold = 3.0;
  static const double moderateFatigueThreshold = 6.0;
  static const double highFatigueThreshold = 8.0;

  // 로컬 저장소 키
  static const String keyUserBaseline = 'user_baseline';
  static const String keyCurrentUserId = 'current_user_id';

  // API 엔드포인트
  static const String apiLogs = '/api/v1/logs';
  static const String apiLogsBatch = '/api/v1/logs/batch';
  static const String apiReportWeekly = '/api/v1/report/weekly';
  static const String apiBaseline = '/api/v1/baseline';
}

