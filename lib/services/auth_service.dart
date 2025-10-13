import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

/// 인증 서비스 (Supabase Auth)
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 현재 로그인된 사용자
  User? get currentUser => _supabase.auth.currentUser;

  /// 인증 상태 스트림
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// 이메일 회원가입
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('회원가입에 실패했습니다.');
      }

      return UserModel(
        id: response.user!.id,
        email: response.user!.email!,
        createdAt: response.user!.createdAt != null
            ? DateTime.parse(response.user!.createdAt!)
            : DateTime.now(),
      );
    } catch (e) {
      throw Exception('회원가입 오류: $e');
    }
  }

  /// 이메일 로그인
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('로그인에 실패했습니다.');
      }

      return UserModel(
        id: response.user!.id,
        email: response.user!.email!,
        createdAt: response.user!.createdAt != null
            ? DateTime.parse(response.user!.createdAt!)
            : DateTime.now(),
      );
    } catch (e) {
      throw Exception('로그인 오류: $e');
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('로그아웃 오류: $e');
    }
  }

  /// 비밀번호 재설정 이메일 발송
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception('비밀번호 재설정 오류: $e');
    }
  }

  /// 현재 사용자 정보 가져오기
  UserModel? getCurrentUserModel() {
    final user = currentUser;
    if (user == null) return null;

    return UserModel(
      id: user.id,
      email: user.email!,
      createdAt: user.createdAt != null
          ? DateTime.parse(user.createdAt!)
          : DateTime.now(),
    );
  }
}

