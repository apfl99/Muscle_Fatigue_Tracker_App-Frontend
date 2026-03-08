import 'package:flutter/material.dart';

import '../model/heatmap_models.dart';
import '../../../widgets/interactive_muscle_3d_viewer.dart';

class MuscleHeatmapContainer extends StatelessWidget {
  const MuscleHeatmapContainer({
    super.key,
    required this.entries,
  });

  final List<MuscleHeatmapEntry> entries;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF121418),
        ),
        child: InteractiveMuscle3DViewer(
          entries: entries,
          borderRadius: 20,
          interactive: true,
          autoRotate: false,
          showHotspots: true,
        ),
      ),
    );
  }
}
