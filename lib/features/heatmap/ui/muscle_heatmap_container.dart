import 'package:flutter/material.dart';

import '../model/heatmap_models.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/interactive_muscle_3d_viewer.dart';

class MuscleHeatmapContainer extends StatefulWidget {
  const MuscleHeatmapContainer({
    super.key,
    required this.entries,
    this.viewerSyncKey,
  });

  final List<MuscleHeatmapEntry> entries;
  final Key? viewerSyncKey;

  @override
  State<MuscleHeatmapContainer> createState() => _MuscleHeatmapContainerState();
}

class _MuscleHeatmapContainerState extends State<MuscleHeatmapContainer> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: AppTheme.cardDecoration(
          color: AppTheme.surface1,
          borderRadius: 24,
        ),
        child: InteractiveMuscle3DViewer(
          key: widget.viewerSyncKey,
          entries: widget.entries,
          borderRadius: 24,
          interactive: true,
          autoRotate: false,
          showHotspots: false,
        ),
      ),
    );
  }
}
