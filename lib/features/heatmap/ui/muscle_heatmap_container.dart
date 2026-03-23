import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../model/heatmap_models.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/heatmap_2d_viewer.dart';
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
  bool _use2DFallback = false;
  bool _fallbackSnackbarShown = false;

  void _switchTo2D() {
    if (!mounted) {
      return;
    }
    if (_fallbackSnackbarShown) {
      return;
    }
    _fallbackSnackbarShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('viewer.interactive3d.optimizing'.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: AppTheme.cardDecoration(
          color: AppTheme.surface1,
          borderRadius: 24,
        ),
        child: _use2DFallback
            ? Heatmap2DViewer(
                entries: widget.entries,
                borderRadius: 24,
              )
            : InteractiveMuscle3DViewer(
                key: widget.viewerSyncKey,
                entries: widget.entries,
                borderRadius: 24,
                interactive: true,
                autoRotate: false,
                showHotspots: false,
                onFallbackTo2D: _switchTo2D,
              ),
      ),
    );
  }
}
