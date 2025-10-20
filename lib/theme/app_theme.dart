import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 앱 전체 테마 (Fitness Health Tracker 스타일)
class AppTheme {
  // 메인 컬러 팔레트 (녹색/검은색 기반)
  static const Color primaryGreen = Color(0xFF00E676);
  static const Color darkGreen = Color(0xFF00C853);
  static const Color accentGreen = Color(0xFF69F0AE);

  // 다크 그레이 배경 (검은색 계열, 너무 검은색은 아님)
  static const Color darkBackground = Color(0xFF121212); // Material Dark 표준
  static const Color cardBackground = Color(0xFF1E1E1E); // 약간 밝은 검은색
  static const Color cardDark = Color(0xFF181818); // 어두운 검은색

  // 피로도 레벨 컬러 (통일된 색상)
  static const Color normalColor = Color(0xFF4CAF50); // 정상 - 초록
  static const Color lightFatigueColor = Color(0xFFFFA726); // 약간 피로 - 주황
  static const Color midFatigueColor = Color(0xFFFF7043); // 피로 누적 - 진한 주황
  static const Color highFatigueColor = Color(0xFFE53935); // 고피로 - 빨강

  // 그라데이션
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGreen, darkGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [cardBackground, cardDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 피로도 점수에 따른 배경 그라디언트 (통일된 색상 기준)
  static LinearGradient fatigueGradient(double fatigue) {
    if (fatigue < 1.1) {
      // 정상 - 초록
      return const LinearGradient(
        colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (fatigue < 1.4) {
      // 약간 피로 - 주황
      return const LinearGradient(
        colors: [Color(0xFFFFA726), Color(0xFFFB8C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (fatigue < 1.8) {
      // 피로 누적 - 진한 주황
      return const LinearGradient(
        colors: [Color(0xFFFF7043), Color(0xFFE64A19)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      // 고피로 - 빨강
      return const LinearGradient(
        colors: [Color(0xFFE53935), Color(0xFFC62828)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
  }

  // 텍스트 스타일 (Google Fonts Poppins - 피트니스/헬스케어 앱에 최적)
  static TextStyle get headlineStyle => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      );

  static TextStyle get titleStyle => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  static TextStyle get bodyStyle => GoogleFonts.poppins(
        fontSize: 14,
        color: const Color(0xFFB0BEC5),
      );

  static TextStyle get captionStyle => GoogleFonts.poppins(
        fontSize: 12,
        color: const Color(0xFF78909C),
      );

  // 카드 스타일
  static BoxDecoration cardDecoration({
    Color? color,
    Gradient? gradient,
    double borderRadius = 20,
  }) {
    return BoxDecoration(
      color: color ?? cardBackground,
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // 버튼 스타일
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryGreen,
    foregroundColor: darkBackground,
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    elevation: 5,
  );

  static ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryGreen,
    side: const BorderSide(color: primaryGreen, width: 2),
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  );

  // 아이콘 버튼 스타일
  static BoxDecoration iconButtonDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? cardBackground,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 5,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  // ThemeData
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: darkBackground,
      cardColor: cardBackground,

      // Google Fonts Poppins 적용
      fontFamily: GoogleFonts.poppins().fontFamily,

      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        iconTheme: const IconThemeData(color: primaryGreen),
        titleTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),

      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentGreen,
        surface: cardBackground,
        error: highFatigueColor,
      ),

      textTheme: TextTheme(
        headlineLarge: headlineStyle,
        headlineMedium: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titleLarge: titleStyle,
        titleMedium: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.poppins(
          fontSize: 16,
          color: const Color(0xFFB0BEC5),
        ),
        bodyMedium: bodyStyle,
        bodySmall: GoogleFonts.poppins(
          fontSize: 13,
          color: const Color(0xFFB0BEC5),
        ),
        labelLarge: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        labelMedium: captionStyle,
        labelSmall: GoogleFonts.poppins(
          fontSize: 11,
          color: const Color(0xFF78909C),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: primaryButtonStyle.copyWith(
          textStyle: WidgetStateProperty.all(
            GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: outlineButtonStyle.copyWith(
          textStyle: WidgetStateProperty.all(
            GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
