/// 앱 설정
class AppConfig {
  // API 설정
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  // Supabase 설정 (실제 값으로 대체 필요)
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'YOUR_SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR_SUPABASE_ANON_KEY');

  // 측정 설정
  static const int measurementDurationSeconds = 5;
  static const int targetSamplingRate = 100; // Hz
  static const int targetSampleCount = measurementDurationSeconds * targetSamplingRate;

  // Baseline 업데이트 가중치
  static const double baselineAlpha = 0.2;

  // 피로도 계산 가중치
  static const double fatigueAlpha = 3.0;
  static const double fatigueBeta = 3.0;
  static const double fatigueGamma = 4.0;
}

