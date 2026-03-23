import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 반응형 UI 헬퍼 클래스
class Responsive {
  /// 화면 너비
  static double width(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// 화면 높이
  static double height(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// 화면 너비 기준 비율
  static double wp(BuildContext context, double percentage) {
    return width(context) * percentage / 100;
  }

  /// 화면 높이 기준 비율
  static double hp(BuildContext context, double percentage) {
    return height(context) * percentage / 100;
  }

  /// 폰트 크기 (화면 너비 기준)
  static double fontSize(BuildContext context, double size) {
    return size * width(context) / 375; // iPhone 11 Pro 기준
  }

  /// 패딩 (화면 너비 기준)
  static double padding(BuildContext context, double size) {
    return size * width(context) / 375;
  }

  /// 작은 화면 여부 (너비 360px 이하)
  static bool isSmallScreen(BuildContext context) {
    return width(context) <= 360;
  }

  /// 중간 화면 여부 (너비 360-600px)
  static bool isMediumScreen(BuildContext context) {
    return width(context) > 360 && width(context) <= 600;
  }

  /// 큰 화면 여부 (너비 600px 이상)
  static bool isLargeScreen(BuildContext context) {
    return width(context) > 600;
  }

  /// 반응형 값 반환
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (width(context) >= 1024) {
      return desktop ?? tablet ?? mobile;
    } else if (width(context) >= 600) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }

  /// 반응형 패딩
  static EdgeInsets responsivePadding(BuildContext context) {
    final width = Responsive.width(context);
    if (width >= 1100) {
      return const EdgeInsets.symmetric(horizontal: 44, vertical: 20);
    }
    if (width >= 768) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 18);
    }
    return AppTheme.pagePadding.copyWith(top: 16, bottom: 16);
  }

  /// 반응형 카드 패딩
  static EdgeInsets cardPadding(BuildContext context) {
    final width = Responsive.width(context);
    if (width >= 1100) {
      return const EdgeInsets.all(28);
    }
    if (width >= 768) {
      return const EdgeInsets.all(24);
    }
    return const EdgeInsets.all(20);
  }
}
