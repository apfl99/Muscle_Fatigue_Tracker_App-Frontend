import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_drawing/path_drawing.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../theme/app_theme.dart';

class Heatmap2DViewer extends StatefulWidget {
  const Heatmap2DViewer({
    super.key,
    required this.entries,
    this.borderRadius = 20,
    this.tintAnimationDuration = const Duration(milliseconds: 800),
    this.auraAnimationDuration = const Duration(milliseconds: 1000),
    this.exposeTestKey = false,
    this.onMuscleTap,
  });

  final List<MuscleHeatmapEntry> entries;
  final double borderRadius;
  final Duration tintAnimationDuration;
  final Duration auraAnimationDuration;
  final bool exposeTestKey;
  final ValueChanged<String>? onMuscleTap;

  @override
  State<Heatmap2DViewer> createState() => _Heatmap2DViewerState();
}

class _Heatmap2DViewerState extends State<Heatmap2DViewer> {
  static const Size _svgViewBoxSize = Size(920, 760);
  static final Future<String> _svgTemplateFuture =
      rootBundle.loadString('assets/images/muscle_anatomy.svg');
  static final List<_MusclePathRegion> _hitRegions = _buildHitRegions();

  Map<String, HeatmapStatus> _previousStatusByCode = const {};
  Map<String, HeatmapStatus> _currentStatusByCode = const {};
  int _animationVersion = 0;

  @override
  void initState() {
    super.initState();
    final normalized = _normalizeStatusByCode(widget.entries);
    _previousStatusByCode = normalized;
    _currentStatusByCode = normalized;
  }

  @override
  void didUpdateWidget(covariant Heatmap2DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final normalized = _normalizeStatusByCode(widget.entries);
    if (mapEquals(_currentStatusByCode, normalized)) {
      return;
    }
    _previousStatusByCode = _currentStatusByCode;
    _currentStatusByCode = normalized;
    _animationVersion += 1;
  }

  @override
  Widget build(BuildContext context) {
    final averageScore = _averageScore(widget.entries);
    final auraColor = _colorForScore(averageScore);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            key: widget.exposeTestKey
                ? const Key('viewer_dynamic_background')
                : null,
            duration: widget.auraAnimationDuration,
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [
                  auraColor.withValues(alpha: 0.32),
                  auraColor.withValues(alpha: 0.08),
                  const Color(0xFF0F132E),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          FutureBuilder<String>(
            future: _svgTemplateFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint(
                  '[Heatmap2DViewer] SVG load failed: ${snapshot.error}',
                );
                return _buildFallbackMap();
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00E676),
                  ),
                );
              }

              final svgTemplate = snapshot.data!;
              return TweenAnimationBuilder<double>(
                key: ValueKey<int>(_animationVersion),
                tween: Tween<double>(begin: 0, end: 1),
                duration: widget.tintAnimationDuration,
                curve: Curves.easeInOut,
                builder: (context, progress, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final painterSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              AppTheme.textHigh,
                              BlendMode.modulate,
                            ),
                            child: SvgPicture.string(
                              svgTemplate,
                              fit: BoxFit.contain,
                              colorMapper: _HeatmapColorMapper(
                                previousStatusByCode: _previousStatusByCode,
                                currentStatusByCode: _currentStatusByCode,
                                progress: progress,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.deferToChild,
                              onTapUp: widget.onMuscleTap == null
                                  ? null
                                  : (details) => _handleTapUp(
                                        details: details,
                                        painterSize: painterSize,
                                      ),
                              child: const ColoredBox(
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, HeatmapStatus> _normalizeStatusByCode(
    List<MuscleHeatmapEntry> entries,
  ) {
    final normalized = <String, HeatmapStatus>{};
    for (final entry in entries) {
      final sourceCode = entry.muscleCode.trim().toLowerCase();
      if (sourceCode.isEmpty) {
        continue;
      }
      final canonicalCode = _canonicalMuscleCode(sourceCode);
      final previous = normalized[canonicalCode];
      if (previous == null ||
          _statusPriority(entry.status) > _statusPriority(previous)) {
        normalized[canonicalCode] = entry.status;
      }
    }
    return normalized;
  }

  String _canonicalMuscleCode(String sourceCode) {
    return _muscleAliases[sourceCode] ?? sourceCode;
  }

  int _statusPriority(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return 4;
      case HeatmapStatus.yellow:
        return 3;
      case HeatmapStatus.green:
        return 2;
      case HeatmapStatus.unknown:
        return 1;
    }
  }

  double _averageScore(List<MuscleHeatmapEntry> entries) {
    if (entries.isEmpty) {
      return 1.0;
    }

    final values = entries.map((entry) {
      if (entry.fatigueScore > 0) {
        return entry.fatigueScore.clamp(0.0, 3.0);
      }
      switch (entry.status) {
        case HeatmapStatus.red:
          return 3.0;
        case HeatmapStatus.yellow:
          return 2.0;
        case HeatmapStatus.green:
          return 1.0;
        case HeatmapStatus.unknown:
          return 1.2;
      }
    }).toList();

    final total = values.fold<double>(0, (sum, value) => sum + value);
    return total / values.length;
  }

  Color _colorForScore(double score) {
    final normalized = score.clamp(1.0, 3.0);
    if (normalized <= 2.0) {
      return Color.lerp(
            const Color(0xFF00E676),
            const Color(0xFFFFA726),
            normalized - 1.0,
          ) ??
          const Color(0xFF00E676);
    }
    return Color.lerp(
          const Color(0xFFFFA726),
          const Color(0xFFE53935),
          normalized - 2.0,
        ) ??
        const Color(0xFFFFA726);
  }

  Widget _buildFallbackMap() {
    return Container(
      color: const Color(0xFF131A30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.accessibility_new_rounded,
              size: 96,
              color: Color(0xFF8E97A8),
            ),
            SizedBox(height: 10),
            Text(
              'viewer.heatmap2d.fallback'.tr(),
              style: TextStyle(color: AppTheme.textLow, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTapUp({
    required TapUpDetails details,
    required Size painterSize,
  }) {
    final contentRect = _resolveContainRect(
      canvasSize: painterSize,
      sourceSize: _svgViewBoxSize,
    );
    if (!contentRect.contains(details.localPosition)) {
      return;
    }

    final local = details.localPosition;
    final mapped = Offset(
      (local.dx - contentRect.left) *
          (_svgViewBoxSize.width / contentRect.width),
      (local.dy - contentRect.top) *
          (_svgViewBoxSize.height / contentRect.height),
    );

    for (final region in _hitRegions) {
      if (region.path.contains(mapped)) {
        HapticFeedback.lightImpact();
        widget.onMuscleTap?.call(region.code);
        return;
      }
    }
  }

  Rect _resolveContainRect({
    required Size canvasSize,
    required Size sourceSize,
  }) {
    if (canvasSize.isEmpty || sourceSize.isEmpty) {
      return Offset.zero & canvasSize;
    }

    final canvasRatio = canvasSize.width / canvasSize.height;
    final sourceRatio = sourceSize.width / sourceSize.height;

    if (canvasRatio > sourceRatio) {
      final height = canvasSize.height;
      final width = height * sourceRatio;
      final dx = (canvasSize.width - width) / 2;
      return Rect.fromLTWH(dx, 0, width, height);
    }

    final width = canvasSize.width;
    final height = width / sourceRatio;
    final dy = (canvasSize.height - height) / 2;
    return Rect.fromLTWH(0, dy, width, height);
  }

  static List<_MusclePathRegion> _buildHitRegions() {
    final regions = <_MusclePathRegion>[];

    for (final segment in _frontSegments) {
      final canonicalCode = _muscleAliases[segment.code] ?? segment.code;
      final path =
          parseSvgPathData(segment.pathData).shift(const Offset(90, 0));
      regions.add(_MusclePathRegion(code: canonicalCode, path: path));
    }

    for (final segment in _backSegments) {
      final canonicalCode = _muscleAliases[segment.code] ?? segment.code;
      final path =
          parseSvgPathData(segment.pathData).shift(const Offset(510, 0));
      regions.add(_MusclePathRegion(code: canonicalCode, path: path));
    }

    regions.sort(
      (a, b) => a.path
          .getBounds()
          .size
          .longestSide
          .compareTo(b.path.getBounds().size.longestSide),
    );
    return regions;
  }
}

class _HeatmapColorMapper extends ColorMapper {
  const _HeatmapColorMapper({
    required this.previousStatusByCode,
    required this.currentStatusByCode,
    required this.progress,
  });

  final Map<String, HeatmapStatus> previousStatusByCode;
  final Map<String, HeatmapStatus> currentStatusByCode;
  final double progress;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final muscleCode = _muscleCodeFromElementId(id);
    if (muscleCode == null) {
      return color;
    }

    final previousStatus =
        previousStatusByCode[muscleCode] ?? HeatmapStatus.unknown;
    final currentStatus =
        currentStatusByCode[muscleCode] ?? HeatmapStatus.unknown;
    final previousColor = _tintColor(previousStatus);
    final currentColor = _tintColor(currentStatus);
    return Color.lerp(previousColor, currentColor, progress) ?? currentColor;
  }

  String? _muscleCodeFromElementId(String? id) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }

    final rawId = id.trim().toLowerCase();
    if (_muscleAliases.containsKey(rawId)) {
      return _muscleAliases[rawId];
    }
    if (_heatmapMuscleCodes.contains(rawId)) {
      return rawId;
    }

    final frontRemoved = rawId.replaceFirst(RegExp(r'_front$'), '');
    if (_heatmapMuscleCodes.contains(frontRemoved)) {
      return frontRemoved;
    }

    final backRemoved = rawId.replaceFirst(RegExp(r'_back$'), '');
    if (_heatmapMuscleCodes.contains(backRemoved)) {
      return backRemoved;
    }

    return _muscleAliases[backRemoved] ?? _muscleAliases[frontRemoved];
  }

  Color _tintColor(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return const Color(0x99E53935);
      case HeatmapStatus.yellow:
        return const Color(0x99FFA726);
      case HeatmapStatus.green:
        return const Color(0x8A00E676);
      case HeatmapStatus.unknown:
        return const Color(0x00000000);
    }
  }
}

const Set<String> _heatmapMuscleCodes = {
  'neck',
  'front_deltoid',
  'lateral_deltoid',
  'rear_deltoid',
  'chest',
  'biceps',
  'triceps',
  'forearm_flexor',
  'forearm_extensor',
  'rectus_abdominis',
  'obliques',
  'hip_flexor',
  'adductors',
  'abductors',
  'quadriceps',
  'hamstrings',
  'tibialis_anterior',
  'calves',
  'trapezius',
  'teres_major',
  'latissimus',
  'erector_spinae',
  'lower_back',
  'glutes',
};

const Map<String, String> _muscleAliases = {
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
  'pectoralis_major': 'chest',
  'pecs': 'chest',
  'chest_major': 'chest',
  'anterior_deltoid': 'front_deltoid',
  'front_delts': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'rear_delts': 'rear_deltoid',
  'triceps_brachii': 'triceps',
  'latissimus_dorsi': 'latissimus',
  'lats': 'latissimus',
  'quads': 'quadriceps',
  'inner_thigh': 'adductors',
  'gluteus_maximus': 'glutes',
  'glute_medius': 'abductors',
  'spinal_erectors': 'erector_spinae',
  'lumbar': 'lower_back',
  'gastrocnemius': 'calves',
  'soleus': 'calves',
  'shin': 'tibialis_anterior',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'upper_trap': 'trapezius',
  'cervical': 'neck',
};

class _MusclePathRegion {
  const _MusclePathRegion({
    required this.code,
    required this.path,
  });

  final String code;
  final Path path;
}

class _HeatmapHitSegment {
  const _HeatmapHitSegment({
    required this.code,
    required this.pathData,
  });

  final String code;
  final String pathData;
}

const List<_HeatmapHitSegment> _frontSegments = [
  _HeatmapHitSegment(
    code: 'neck',
    pathData:
        'M161 84 C168 72 192 72 199 84 L199 112 C192 124 168 124 161 112 Z',
  ),
  _HeatmapHitSegment(
    code: 'front_deltoid',
    pathData:
        'M95 136 C119 108 146 112 162 138 L152 178 C132 182 110 174 95 150 Z M265 136 C241 108 214 112 198 138 L208 178 C228 182 250 174 265 150 Z',
  ),
  _HeatmapHitSegment(
    code: 'lateral_deltoid',
    pathData:
        'M104 148 C118 124 134 124 146 142 L140 174 C124 178 112 172 104 158 Z M256 148 C242 124 226 124 214 142 L220 174 C236 178 248 172 256 158 Z',
  ),
  _HeatmapHitSegment(
    code: 'chest',
    pathData:
        'M132 148 C148 132 212 132 228 148 L218 210 C204 224 156 224 142 210 Z',
  ),
  _HeatmapHitSegment(
    code: 'biceps',
    pathData:
        'M76 208 C74 242 82 266 94 276 L112 236 C114 204 102 174 86 174 Z M284 208 C286 242 278 266 266 276 L248 236 C246 204 258 174 274 174 Z',
  ),
  _HeatmapHitSegment(
    code: 'forearm_flexor',
    pathData:
        'M82 286 C98 294 98 330 86 364 L70 356 C72 328 70 304 82 286 Z M278 286 C262 294 262 330 274 364 L290 356 C288 328 290 304 278 286 Z',
  ),
  _HeatmapHitSegment(
    code: 'rectus_abdominis',
    pathData:
        'M154 220 C166 214 194 214 206 220 L206 330 C194 346 166 346 154 330 Z',
  ),
  _HeatmapHitSegment(
    code: 'obliques',
    pathData:
        'M128 220 C144 228 146 322 132 338 L112 312 L114 238 Z M232 220 C216 228 214 322 228 338 L248 312 L246 238 Z',
  ),
  _HeatmapHitSegment(
    code: 'hip_flexor',
    pathData:
        'M148 344 C164 336 196 336 212 344 L208 376 C192 388 168 388 152 376 Z',
  ),
  _HeatmapHitSegment(
    code: 'adductors',
    pathData:
        'M160 386 C170 380 190 380 200 386 L194 448 C186 462 174 462 166 448 Z',
  ),
  _HeatmapHitSegment(
    code: 'quadriceps',
    pathData:
        'M126 384 C142 386 154 410 152 454 L142 552 C124 548 110 524 110 478 Z M234 384 C218 386 206 410 208 454 L218 552 C236 548 250 524 250 478 Z',
  ),
  _HeatmapHitSegment(
    code: 'tibialis_anterior',
    pathData:
        'M122 560 C134 562 136 618 124 676 L108 672 C104 626 108 578 122 560 Z M238 560 C226 562 224 618 236 676 L252 672 C256 626 252 578 238 560 Z',
  ),
  _HeatmapHitSegment(
    code: 'calves',
    pathData:
        'M90 560 C102 574 104 640 94 700 L78 696 C74 640 78 588 90 560 Z M270 560 C258 574 256 640 266 700 L282 696 C286 640 282 588 270 560 Z',
  ),
];

const List<_HeatmapHitSegment> _backSegments = [
  _HeatmapHitSegment(
    code: 'neck',
    pathData:
        'M161 84 C168 72 192 72 199 84 L199 112 C192 124 168 124 161 112 Z',
  ),
  _HeatmapHitSegment(
    code: 'trapezius',
    pathData:
        'M138 126 C154 108 206 108 222 126 L212 182 C202 192 158 192 148 182 Z',
  ),
  _HeatmapHitSegment(
    code: 'rear_deltoid',
    pathData:
        'M96 144 C118 116 146 120 162 146 L154 180 C132 186 112 178 96 160 Z M264 144 C242 116 214 120 198 146 L206 180 C228 186 248 178 264 160 Z',
  ),
  _HeatmapHitSegment(
    code: 'triceps',
    pathData:
        'M80 198 C74 234 82 262 96 278 L116 238 C118 206 104 178 90 174 Z M280 198 C286 234 278 262 264 278 L244 238 C242 206 256 178 270 174 Z',
  ),
  _HeatmapHitSegment(
    code: 'forearm_extensor',
    pathData:
        'M86 286 C104 294 106 332 96 368 L78 362 C78 328 74 304 86 286 Z M274 286 C256 294 254 332 264 368 L282 362 C282 328 286 304 274 286 Z',
  ),
  _HeatmapHitSegment(
    code: 'teres_major',
    pathData:
        'M126 192 C144 180 154 180 164 196 L154 224 C138 226 130 218 126 192 Z M234 192 C216 180 206 180 196 196 L206 224 C222 226 230 218 234 192 Z',
  ),
  _HeatmapHitSegment(
    code: 'latissimus',
    pathData:
        'M110 210 C130 204 150 214 160 240 L150 320 C132 330 116 314 110 286 Z M250 210 C230 204 210 214 200 240 L210 320 C228 330 244 314 250 286 Z',
  ),
  _HeatmapHitSegment(
    code: 'erector_spinae',
    pathData:
        'M164 218 C170 212 176 212 182 220 L182 372 C176 382 170 382 164 372 Z M196 218 C190 212 184 212 178 220 L178 372 C184 382 190 382 196 372 Z',
  ),
  _HeatmapHitSegment(
    code: 'lower_back',
    pathData:
        'M150 336 C164 330 196 330 210 336 L206 382 C194 392 166 392 154 382 Z',
  ),
  _HeatmapHitSegment(
    code: 'abductors',
    pathData:
        'M118 336 C134 338 142 356 140 386 L122 408 C112 390 108 364 118 336 Z M242 336 C226 338 218 356 220 386 L238 408 C248 390 252 364 242 336 Z',
  ),
  _HeatmapHitSegment(
    code: 'glutes',
    pathData:
        'M132 388 C148 378 166 380 176 396 L172 446 C156 458 140 456 130 438 Z M228 388 C212 378 194 380 184 396 L188 446 C204 458 220 456 230 438 Z',
  ),
  _HeatmapHitSegment(
    code: 'hamstrings',
    pathData:
        'M126 456 C142 460 152 484 150 528 L144 614 C126 610 112 588 112 548 Z M234 456 C218 460 208 484 210 528 L216 614 C234 610 248 588 248 548 Z',
  ),
  _HeatmapHitSegment(
    code: 'calves',
    pathData:
        'M120 620 C132 624 132 672 122 716 L106 712 C100 676 102 636 120 620 Z M240 620 C228 624 228 672 238 716 L254 712 C260 676 258 636 240 620 Z',
  ),
];
