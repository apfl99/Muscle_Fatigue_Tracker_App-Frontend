import 'package:flutter/material.dart';

import '../model/heatmap_models.dart';

class HeatmapPalette {
  const HeatmapPalette._();

  static const Color red = Color(0xFFFF4D4F);
  static const Color yellow = Color(0xFFF5C542);
  static const Color green = Color(0xFF4CD97B);
  static const Color neutral = Color(0x00000000);

  static Color colorForStatus(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return red;
      case HeatmapStatus.yellow:
        return yellow;
      case HeatmapStatus.green:
        return green;
      case HeatmapStatus.unknown:
        return neutral;
    }
  }

  static String labelForStatus(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return '회복 필요 (24시간 이내)';
      case HeatmapStatus.yellow:
        return '회복 중 (24~48시간)';
      case HeatmapStatus.green:
        return '회복 완료 (48시간+ 또는 기록 없음)';
      case HeatmapStatus.unknown:
        return '데이터 수집 중';
    }
  }
}
