import 'package:supabase_flutter/supabase_flutter.dart';

import '../model/heatmap_models.dart';

class HeatmapApiException implements Exception {
  const HeatmapApiException({
    required this.message,
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  String toString() {
    if (statusCode == null) {
      return 'HeatmapApiException: $message';
    }
    return 'HeatmapApiException($statusCode): $message';
  }
}

class HeatmapApiClient {
  HeatmapApiClient({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<MuscleHeatmapEntry>> fetchHeatmapStatus() async {
    try {
      final response = await _runWithSessionRetry<dynamic>((user) {
        return _supabase.rpc(
          'get_muscle_heatmap_status',
          params: {'p_user_id': user.id},
        );
      });
      final decoded = _decodeJsonList(response);
      return decoded
          .map((entry) => MuscleHeatmapEntry.fromJson(entry))
          .where((entry) => entry.muscleCode.isNotEmpty)
          .toList();
    } on PostgrestException catch (error) {
      throw HeatmapApiException(
        message: _postgrestMessage(error),
        statusCode: _tryParseCode(error.code),
      );
    }
  }

  Future<List<ExerciseSuggestion>> searchExercises({
    required String keyword,
  }) async {
    if (keyword.trim().isEmpty) {
      return const [];
    }

    try {
      final response = await _runWithSessionRetry<dynamic>((_) {
        // 사용자 입력 원문(영문/한글/초성)을 그대로 전달한다.
        return _supabase.rpc(
          'search_exercises',
          params: {'p_keyword': keyword},
        );
      });
      final decoded = _decodeJsonList(response);
      return decoded
          .map((entry) => ExerciseSuggestion.fromJson(entry))
          .where((entry) => entry.id.isNotEmpty && entry.name.isNotEmpty)
          .toList();
    } on PostgrestException catch (error) {
      throw HeatmapApiException(
        message: _postgrestMessage(error),
        statusCode: _tryParseCode(error.code),
      );
    }
  }

  Future<void> insertWorkoutLog({required WorkoutLogDraft draft}) async {
    try {
      await _runWithSessionRetry<void>((user) async {
        await _supabase.from('workout_logs').insert(
              draft.toInsertPayload(userId: user.id),
            );
      });
    } on PostgrestException catch (error) {
      throw HeatmapApiException(
        message: _postgrestMessage(error),
        statusCode: _tryParseCode(error.code),
      );
    }
  }

  Future<T> _runWithSessionRetry<T>(
    Future<T> Function(User user) action,
  ) async {
    var user = await _requireCurrentUser();
    try {
      return await action(user);
    } on PostgrestException catch (error) {
      if (_isUnauthorized(error)) {
        user = await _refreshAnonymousSession();
        return action(user);
      }
      rethrow;
    } on AuthException {
      user = await _refreshAnonymousSession();
      return action(user);
    }
  }

  Future<User> _requireCurrentUser() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser != null) {
      return currentUser;
    }

    try {
      final userResponse = await _supabase.auth.getUser();
      final user = userResponse.user;
      if (user != null) {
        return user;
      }
    } on AuthException {
      // 익명 세션 재생성으로 복구 시도
    } catch (_) {
      // 익명 세션 재생성으로 복구 시도
    }

    return _signInAnonymously();
  }

  Future<User> _refreshAnonymousSession() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // signOut 실패는 무시하고 재로그인을 시도한다.
    }
    return _signInAnonymously();
  }

  Future<User> _signInAnonymously() async {
    final response = await _supabase.auth.signInAnonymously();
    final user = response.user;
    if (user == null) {
      throw const HeatmapApiException(
        message: '익명 세션 생성에 실패했습니다.',
        statusCode: 401,
      );
    }
    return user;
  }

  bool _isUnauthorized(PostgrestException error) {
    final code = error.code?.trim().toUpperCase();
    if (code == '401' || code == 'PGRST301' || code == 'PGRST302') {
      return true;
    }

    final message = error.message.toLowerCase();
    return message.contains('401') ||
        message.contains('unauthorized') ||
        message.contains('jwt');
  }

  List<Map<String, dynamic>> _decodeJsonList(dynamic response) {
    final decoded = response;
    if (decoded is! List) {
      throw const HeatmapApiException(
        message: 'API 응답 형식이 배열이 아닙니다.',
      );
    }

    return decoded
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  String _postgrestMessage(PostgrestException error) {
    final details = error.details?.toString() ?? '';
    final hint = error.hint?.toString() ?? '';
    final parts = <String>[
      if (error.message.trim().isNotEmpty) error.message.trim(),
      if (details.trim().isNotEmpty) details.trim(),
      if (hint.trim().isNotEmpty) hint.trim(),
    ];
    if (parts.isEmpty) {
      return '알 수 없는 서버 오류가 발생했습니다.';
    }
    return parts.join(' • ');
  }

  int? _tryParseCode(String? rawCode) {
    if (rawCode == null) {
      return null;
    }
    return int.tryParse(rawCode);
  }

  void dispose() {
    // SupabaseClient는 앱 전역으로 관리되므로 별도 dispose가 필요 없다.
  }
}
