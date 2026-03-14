/// 서버 설정 관리
/// API 서버 URL과 기타 설정을 관리합니다.
library;

import 'dart:convert';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void print(Object? message) => appLog(message);

class ServerConfig {
  static const String _configKey = 'server_config';

  String apiBaseUrl;
  String modelBaseUrl;
  String apiVersion;
  int timeoutSeconds;
  int maxRetries;
  bool enableLogging;
  bool isTestMode;

  ServerConfig({
    this.apiBaseUrl = 'https://merry99-musclecare-fastapi.hf.space',
    this.modelBaseUrl = 'https://merry99-musclecare-train-ai.hf.space',
    this.apiVersion = '',
    this.timeoutSeconds = 30,
    this.maxRetries = 3,
    this.enableLogging = true,
    this.isTestMode = false,
  });

  /// SharedPreferences에서 설정 로드
  static Future<ServerConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);

      if (configJson != null) {
        final configMap = jsonDecode(configJson) as Map<String, dynamic>;
        return ServerConfig.fromJson(configMap);
      }
    } catch (e) {
      print('⚠️ 설정 로드 실패, 기본값 사용: $e');
    }

    // 기본 설정 반환
    return ServerConfig();
  }

  /// SharedPreferences에 설정 저장
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(toJson());
      await prefs.setString(_configKey, configJson);
      print('✅ 서버 설정 저장 완료');
    } catch (e) {
      print('❌ 설정 저장 실패: $e');
    }
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'api_base_url': apiBaseUrl,
      'model_base_url': modelBaseUrl,
      'api_version': apiVersion,
      'timeout_seconds': timeoutSeconds,
      'max_retries': maxRetries,
      'enable_logging': enableLogging,
      'is_test_mode': isTestMode,
    };
  }

  /// JSON에서 객체 생성
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      apiBaseUrl:
          json['api_base_url'] ?? json['base_url'] ?? 'http://localhost:7860',
      modelBaseUrl:
          json['model_base_url'] ?? json['base_url'] ?? 'http://localhost:7860',
      apiVersion: json['api_version'] ?? 'v1',
      timeoutSeconds: json['timeout_seconds'] ?? 30,
      maxRetries: json['max_retries'] ?? 3,
      enableLogging: json['enable_logging'] ?? true,
      isTestMode: json['is_test_mode'] ?? false,
    );
  }

  /// API 엔드포인트 URL 생성
  String getApiUrl(String endpoint) => _buildUrl(apiBaseUrl, endpoint);

  String getModelUrl(String endpoint) => _buildUrl(modelBaseUrl, endpoint);

  /// Upload Dataset API URL
  String get uploadDatasetUrl => getApiUrl('/upload_dataset');

  /// 설정 유효성 검사
  bool get isValid {
    return apiBaseUrl.isNotEmpty &&
        Uri.tryParse(apiBaseUrl) != null &&
        modelBaseUrl.isNotEmpty &&
        Uri.tryParse(modelBaseUrl) != null &&
        timeoutSeconds > 0 &&
        maxRetries >= 0;
  }

  /// 설정 정보 출력
  void printConfig() {
    if (enableLogging) {
      print('📡 서버 설정:');
      print('   API Base URL: $apiBaseUrl');
      print('   Model Base URL: $modelBaseUrl');
      print('   API Version: $apiVersion');
      print('   Timeout: ${timeoutSeconds}s');
      print('   Max Retries: $maxRetries');
      print('   Logging: ${enableLogging ? "ON" : "OFF"}');
    }
  }

  @override
  String toString() {
    return 'ServerConfig(apiBaseUrl: $apiBaseUrl, modelBaseUrl: $modelBaseUrl, apiVersion: $apiVersion)';
  }

  String _buildUrl(String base, String endpoint) {
    final cleanBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return '$cleanBase$cleanEndpoint';
  }
}

/// 전역 설정 인스턴스
ServerConfig? _globalConfig;

/// 전역 설정 가져오기
Future<ServerConfig> getServerConfig() async {
  _globalConfig ??= await ServerConfig.load();
  return _globalConfig!;
}

/// 전역 설정 업데이트
Future<void> updateServerConfig(ServerConfig config) async {
  await config.save();
  _globalConfig = config;
}
