import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
        return 'heatmap.palette.red'.tr();
      case HeatmapStatus.yellow:
        return 'heatmap.palette.yellow'.tr();
      case HeatmapStatus.green:
        return 'heatmap.palette.green'.tr();
      case HeatmapStatus.unknown:
        return 'heatmap.palette.unknown'.tr();
    }
  }
}
