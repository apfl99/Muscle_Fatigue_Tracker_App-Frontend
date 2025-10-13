import 'package:dio/dio.dart';
import '../models/fatigue_result.dart';
import '../models/user_baseline.dart';

/// API 서비스 (FastAPI 백엔드 연동)
class ApiService {
  late final Dio _dio;
  static const String baseUrl = 'http://localhost:8000'; // TODO: 환경변수로 변경

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  /// 인증 토큰 설정
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 측정 결과 업로드
  Future<void> uploadFatigueResult(FatigueResult result) async {
    try {
      await _dio.post('/api/v1/logs', data: result.toJson());
    } catch (e) {
      throw Exception('측정 결과 업로드 실패: $e');
    }
  }

  /// 여러 측정 결과 일괄 업로드
  Future<void> uploadBatchResults(List<FatigueResult> results) async {
    try {
      await _dio.post(
        '/api/v1/logs/batch',
        data: {'results': results.map((r) => r.toJson()).toList()},
      );
    } catch (e) {
      throw Exception('일괄 업로드 실패: $e');
    }
  }

  /// 주간 통계 리포트 조회
  Future<Map<String, dynamic>> getWeeklyReport() async {
    try {
      final response = await _dio.get('/api/v1/report/weekly');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('주간 리포트 조회 실패: $e');
    }
  }

  /// 사용자 baseline 서버 동기화
  Future<void> syncBaseline(UserBaseline baseline) async {
    try {
      await _dio.post('/api/v1/baseline', data: baseline.toJson());
    } catch (e) {
      throw Exception('Baseline 동기화 실패: $e');
    }
  }

  /// 사용자 baseline 서버에서 불러오기
  Future<UserBaseline?> fetchBaseline(String userId) async {
    try {
      final response = await _dio.get('/api/v1/baseline/$userId');
      if (response.data == null) return null;
      return UserBaseline.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        return null; // baseline이 아직 없음
      }
      throw Exception('Baseline 조회 실패: $e');
    }
  }

  /// 최근 측정 결과 조회
  Future<List<FatigueResult>> fetchRecentResults({int limit = 30}) async {
    try {
      final response = await _dio.get(
        '/api/v1/logs',
        queryParameters: {'limit': limit},
      );
      final data = response.data as List;
      return data.map((json) => FatigueResult.fromJson(json)).toList();
    } catch (e) {
      throw Exception('측정 결과 조회 실패: $e');
    }
  }
}

