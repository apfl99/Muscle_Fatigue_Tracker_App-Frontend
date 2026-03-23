import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium dark design tokens + global theme.
class AppTheme {
  // Core palette
  static const Color background = Color(0xFF090B10);
  static const Color surface1 = Color(0xFF121620);
  static const Color surface2 = Color(0xFF1C212D);
  static const Color accentBrand = Color(0xFF00F58A);
  static const Color accentDanger = Color(0xFFFF3B30);
  static const Color ctaOnBrand = Color(0xFF000000); // required contrast

  // Compatibility aliases (existing code migration-safe)
  static const Color darkBackground = background;
  static const Color cardBackground = surface1;
  static const Color cardDark = surface2;
  static const Color primaryGreen = accentBrand;
  static const Color darkGreen = Color(0xFF00C77A);
  static const Color accentGreen = Color(0xFF6CFFC1);

  // Typography colors
  static Color get textHigh => Colors.white.withValues(alpha: 0.92);
  static Color get textMedium => Colors.white.withValues(alpha: 0.65);
  static Color get textLow => Colors.white.withValues(alpha: 0.40);

  // Border token
  static Color get borderSubtle => Colors.white.withValues(alpha: 0.04);

  // Layout/shape tokens
  static const double pageHorizontalPaddingValue = 24.0;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageHorizontalPaddingValue,
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(24.0),
  );
  static const BorderRadius buttonRadius = BorderRadius.all(
    Radius.circular(16.0),
  );

  static const SizedBox gap8 = SizedBox(height: 8.0);
  static const SizedBox gap16 = SizedBox(height: 16.0);
  static const SizedBox gap24 = SizedBox(height: 24.0);

  // Recovery colors
  static const Color normalColor = accentBrand;
  static const Color lightFatigueColor = Color(0xFFFFB84D);
  static const Color midFatigueColor = Color(0xFFFF8B57);
  static const Color highFatigueColor = accentDanger;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentBrand, darkGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [surface1, surface2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient chartGlowGradient(Color color) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withValues(alpha: 0.38),
        color.withValues(alpha: 0.10),
        color.withValues(alpha: 0.00),
      ],
    );
  }

  static LinearGradient fatigueGradient(double fatigue) {
    if (fatigue < 1.1) {
      return const LinearGradient(
        colors: [Color(0xFF16D98B), Color(0xFF0E7E5D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (fatigue < 1.4) {
      return const LinearGradient(
        colors: [Color(0xFFFFB84D), Color(0xFFB6731F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (fatigue < 1.8) {
      return const LinearGradient(
        colors: [Color(0xFFFF8B57), Color(0xFFB8562D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      return const LinearGradient(
        colors: [Color(0xFFFF5A54), Color(0xFFAD2B25)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
  }

  // Typography tokens (Inter)
  static TextStyle get displayLargeStyle => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: textHigh,
      );

  static TextStyle get titleLargeStyle => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: textHigh,
      );

  static TextStyle get bodyLargeStyle => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: textHigh,
      );

  static TextStyle get bodyMediumStyle => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.0,
        height: 1.5,
        color: textMedium,
      );

  static TextStyle get labelSmallStyle => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: textLow,
      );

  // Compatibility typography aliases
  static TextStyle get headlineStyle => displayLargeStyle;
  static TextStyle get titleStyle => titleLargeStyle;
  static TextStyle get bodyStyle => bodyMediumStyle;
  static TextStyle get captionStyle => labelSmallStyle;

  static EdgeInsets resolvedPagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1100) {
      return const EdgeInsets.symmetric(horizontal: 44.0);
    }
    if (width >= 768) {
      return const EdgeInsets.symmetric(horizontal: 32.0);
    }
    return pagePadding;
  }

  static BorderRadius radius(double value) {
    return BorderRadius.circular(value);
  }

  // Card style (no shadows; subtle glass cut border)
  static BoxDecoration cardDecoration({
    Color? color,
    Gradient? gradient,
    double borderRadius = 24,
    Border? border,
    double borderWidth = 1,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: gradient == null ? (color ?? surface1) : color,
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ??
          Border.all(
            color: borderColor ?? borderSubtle,
            width: borderWidth,
          ),
    );
  }

  // Button styles
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: accentBrand,
    foregroundColor: ctaOnBrand,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: buttonRadius,
    ),
    textStyle: bodyLargeStyle.copyWith(fontWeight: FontWeight.w700),
  );

  static ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: textHigh,
    side: BorderSide(color: borderSubtle, width: 1),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: buttonRadius,
    ),
    textStyle: bodyLargeStyle.copyWith(fontWeight: FontWeight.w600),
  );

  // Icon container style
  static BoxDecoration iconButtonDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? surface2,
      borderRadius: buttonRadius,
      border: Border.all(
        color: borderSubtle,
        width: 1,
      ),
    );
  }

  // ThemeData
  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: displayLargeStyle,
      titleLarge: titleLargeStyle,
      bodyLarge: bodyLargeStyle,
      bodyMedium: bodyMediumStyle,
      labelSmall: labelSmallStyle,
      titleMedium: bodyLargeStyle.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: bodyLargeStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      primaryColor: accentBrand,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        primary: accentBrand,
        secondary: accentBrand,
        surface: surface1,
        onPrimary: ctaOnBrand,
        onSurface: textHigh,
        error: accentDanger,
        onError: textHigh,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textHigh,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(
            color: borderSubtle,
            width: 1,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderSubtle,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: outlineButtonStyle),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: surface2,
          foregroundColor: textHigh,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: buttonRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: bodyMediumStyle.copyWith(color: textLow),
        labelStyle: bodyMediumStyle.copyWith(color: textMedium),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: buttonRadius,
          borderSide: BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: buttonRadius,
          borderSide: BorderSide(color: accentBrand.withValues(alpha: 0.60)),
        ),
        border: OutlineInputBorder(
          borderRadius: buttonRadius,
          borderSide: BorderSide(color: borderSubtle),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: bodyMediumStyle.copyWith(color: textHigh),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: buttonRadius),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface2,
        shape: RoundedRectangleBorder(
          borderRadius: buttonRadius,
          side: BorderSide(color: borderSubtle),
        ),
        labelStyle: bodyMediumStyle.copyWith(
          color: textMedium,
        ),
      ),
      splashColor: accentBrand.withValues(alpha: 0.10),
      highlightColor: accentBrand.withValues(alpha: 0.08),
    );
  }
}
