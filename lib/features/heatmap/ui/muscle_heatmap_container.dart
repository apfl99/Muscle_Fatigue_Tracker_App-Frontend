import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/heatmap_models.dart';
import 'heatmap_palette.dart';

enum HeatmapBodyView {
  front,
  back,
}

extension HeatmapBodyViewLabel on HeatmapBodyView {
  String get label {
    switch (this) {
      case HeatmapBodyView.front:
        return '전면';
      case HeatmapBodyView.back:
        return '후면';
    }
  }
}

class MuscleHeatmapContainer extends StatelessWidget {
  const MuscleHeatmapContainer({
    super.key,
    required this.bodyView,
    required this.statusByMuscleCode,
  });

  final HeatmapBodyView bodyView;
  final Map<String, HeatmapStatus> statusByMuscleCode;

  @override
  Widget build(BuildContext context) {
    final overlaySvg = _buildMaskSvg(
      bodyView: bodyView,
      statusByMuscleCode: statusByMuscleCode,
    );
    final statusSignature = _statusSignature(
      bodyView: bodyView,
      statusByMuscleCode: statusByMuscleCode,
    );

    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 360 / 760,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF22242A), Color(0xFF121418)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SvgPicture.asset(
                    _baseAssetPath(bodyView),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Opacity(
                    opacity: 0.9,
                    child: SvgPicture.string(
                      overlaySvg,
                      key: ValueKey(statusSignature),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _baseAssetPath(HeatmapBodyView bodyView) {
    switch (bodyView) {
      case HeatmapBodyView.front:
        return 'assets/heatmap/body_front_3d.svg';
      case HeatmapBodyView.back:
        return 'assets/heatmap/body_back_3d.svg';
    }
  }

  String _statusSignature({
    required HeatmapBodyView bodyView,
    required Map<String, HeatmapStatus> statusByMuscleCode,
  }) {
    final sortedEntries = statusByMuscleCode.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final normalized = sortedEntries
        .map((entry) => '${entry.key}:${entry.value.rawValue}')
        .join('|');
    return '${bodyView.name}|$normalized';
  }

  String _buildMaskSvg({
    required HeatmapBodyView bodyView,
    required Map<String, HeatmapStatus> statusByMuscleCode,
  }) {
    final segments =
        bodyView == HeatmapBodyView.front ? _frontSegments : _backSegments;

    final buffer = StringBuffer();
    buffer.writeln(
      '<svg viewBox="0 0 360 760" xmlns="http://www.w3.org/2000/svg">',
    );
    buffer.writeln(
      '<g id="heatmap-mask-layer" style="mix-blend-mode:multiply">',
    );

    for (final segment in segments) {
      final status = _resolveStatus(
        segment: segment,
        statusByMuscleCode: statusByMuscleCode,
      );
      final color = _toHexColor(HeatmapPalette.colorForStatus(status));
      final opacity = _opacityForStatus(status);
      buffer.writeln(
        '<path id="${segment.code}" d="${segment.pathData}" fill="$color" fill-opacity="$opacity" stroke="none" />',
      );
    }

    buffer.writeln('</g>');
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  HeatmapStatus _resolveStatus({
    required _HeatmapSegment segment,
    required Map<String, HeatmapStatus> statusByMuscleCode,
  }) {
    final direct = statusByMuscleCode[segment.code];
    if (direct != null) {
      return direct;
    }

    for (final alias in segment.aliases) {
      final aliasValue = statusByMuscleCode[alias];
      if (aliasValue != null) {
        return aliasValue;
      }
    }

    return HeatmapStatus.unknown;
  }

  String _toHexColor(Color color) {
    final red = (color.r * 255.0).round().clamp(0, 255);
    final green = (color.g * 255.0).round().clamp(0, 255);
    final blue = (color.b * 255.0).round().clamp(0, 255);
    final rgb = (red << 16) | (green << 8) | blue;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  String _opacityForStatus(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return '0.64';
      case HeatmapStatus.yellow:
        return '0.58';
      case HeatmapStatus.green:
        return '0.50';
      case HeatmapStatus.unknown:
        return '0.0';
    }
  }
}

class _HeatmapSegment {
  const _HeatmapSegment({
    required this.code,
    required this.pathData,
    this.aliases = const [],
  });

  final String code;
  final String pathData;
  final List<String> aliases;
}

const List<_HeatmapSegment> _frontSegments = [
  _HeatmapSegment(
    code: 'neck',
    pathData:
        'M161 84 C168 72 192 72 199 84 L199 112 C192 124 168 124 161 112 Z',
    aliases: ['cervical'],
  ),
  _HeatmapSegment(
    code: 'front_deltoid',
    pathData:
        'M95 136 C119 108 146 112 162 138 L152 178 C132 182 110 174 95 150 Z M265 136 C241 108 214 112 198 138 L208 178 C228 182 250 174 265 150 Z',
    aliases: ['anterior_deltoid'],
  ),
  _HeatmapSegment(
    code: 'chest',
    pathData:
        'M132 148 C148 132 212 132 228 148 L218 210 C204 224 156 224 142 210 Z',
    aliases: ['pectoralis_major', 'pecs'],
  ),
  _HeatmapSegment(
    code: 'biceps',
    pathData:
        'M76 208 C74 242 82 266 94 276 L112 236 C114 204 102 174 86 174 Z M284 208 C286 242 278 266 266 276 L248 236 C246 204 258 174 274 174 Z',
    aliases: ['biceps_brachii'],
  ),
  _HeatmapSegment(
    code: 'forearm_flexor',
    pathData:
        'M82 286 C98 294 98 330 86 364 L70 356 C72 328 70 304 82 286 Z M278 286 C262 294 262 330 274 364 L290 356 C288 328 290 304 278 286 Z',
    aliases: ['forearm', 'wrist_flexor'],
  ),
  _HeatmapSegment(
    code: 'rectus_abdominis',
    pathData:
        'M154 220 C166 214 194 214 206 220 L206 330 C194 346 166 346 154 330 Z',
    aliases: ['abs', 'abdominals'],
  ),
  _HeatmapSegment(
    code: 'obliques',
    pathData:
        'M128 220 C144 228 146 322 132 338 L112 312 L114 238 Z M232 220 C216 228 214 322 228 338 L248 312 L246 238 Z',
  ),
  _HeatmapSegment(
    code: 'hip_flexor',
    pathData:
        'M148 344 C164 336 196 336 212 344 L208 376 C192 388 168 388 152 376 Z',
    aliases: ['iliopsoas'],
  ),
  _HeatmapSegment(
    code: 'adductors',
    pathData:
        'M160 386 C170 380 190 380 200 386 L194 448 C186 462 174 462 166 448 Z',
    aliases: ['inner_thigh'],
  ),
  _HeatmapSegment(
    code: 'quadriceps',
    pathData:
        'M126 384 C142 386 154 410 152 454 L142 552 C124 548 110 524 110 478 Z M234 384 C218 386 206 410 208 454 L218 552 C236 548 250 524 250 478 Z',
    aliases: ['quads'],
  ),
  _HeatmapSegment(
    code: 'tibialis_anterior',
    pathData:
        'M122 560 C134 562 136 618 124 676 L108 672 C104 626 108 578 122 560 Z M238 560 C226 562 224 618 236 676 L252 672 C256 626 252 578 238 560 Z',
    aliases: ['shin'],
  ),
  _HeatmapSegment(
    code: 'calves',
    pathData:
        'M90 560 C102 574 104 640 94 700 L78 696 C74 640 78 588 90 560 Z M270 560 C258 574 256 640 266 700 L282 696 C286 640 282 588 270 560 Z',
    aliases: ['gastrocnemius', 'soleus'],
  ),
];

const List<_HeatmapSegment> _backSegments = [
  _HeatmapSegment(
    code: 'neck',
    pathData:
        'M161 84 C168 72 192 72 199 84 L199 112 C192 124 168 124 161 112 Z',
    aliases: ['cervical'],
  ),
  _HeatmapSegment(
    code: 'trapezius',
    pathData:
        'M138 126 C154 108 206 108 222 126 L212 182 C202 192 158 192 148 182 Z',
    aliases: ['upper_trap'],
  ),
  _HeatmapSegment(
    code: 'rear_deltoid',
    pathData:
        'M96 144 C118 116 146 120 162 146 L154 180 C132 186 112 178 96 160 Z M264 144 C242 116 214 120 198 146 L206 180 C228 186 248 178 264 160 Z',
    aliases: ['posterior_deltoid'],
  ),
  _HeatmapSegment(
    code: 'triceps',
    pathData:
        'M80 198 C74 234 82 262 96 278 L116 238 C118 206 104 178 90 174 Z M280 198 C286 234 278 262 264 278 L244 238 C242 206 256 178 270 174 Z',
    aliases: ['triceps_brachii'],
  ),
  _HeatmapSegment(
    code: 'forearm_extensor',
    pathData:
        'M86 286 C104 294 106 332 96 368 L78 362 C78 328 74 304 86 286 Z M274 286 C256 294 254 332 264 368 L282 362 C282 328 286 304 274 286 Z',
    aliases: ['wrist_extensor'],
  ),
  _HeatmapSegment(
    code: 'teres_major',
    pathData:
        'M126 192 C144 180 154 180 164 196 L154 224 C138 226 130 218 126 192 Z M234 192 C216 180 206 180 196 196 L206 224 C222 226 230 218 234 192 Z',
  ),
  _HeatmapSegment(
    code: 'lats',
    pathData:
        'M110 210 C130 204 150 214 160 240 L150 320 C132 330 116 314 110 286 Z M250 210 C230 204 210 214 200 240 L210 320 C228 330 244 314 250 286 Z',
    aliases: ['latissimus_dorsi'],
  ),
  _HeatmapSegment(
    code: 'erector_spinae',
    pathData:
        'M164 218 C170 212 176 212 182 220 L182 372 C176 382 170 382 164 372 Z M196 218 C190 212 184 212 178 220 L178 372 C184 382 190 382 196 372 Z',
    aliases: ['spinal_erectors'],
  ),
  _HeatmapSegment(
    code: 'lower_back',
    pathData:
        'M150 336 C164 330 196 330 210 336 L206 382 C194 392 166 392 154 382 Z',
    aliases: ['lumbar'],
  ),
  _HeatmapSegment(
    code: 'abductors',
    pathData:
        'M118 336 C134 338 142 356 140 386 L122 408 C112 390 108 364 118 336 Z M242 336 C226 338 218 356 220 386 L238 408 C248 390 252 364 242 336 Z',
    aliases: ['glute_medius'],
  ),
  _HeatmapSegment(
    code: 'glutes',
    pathData:
        'M132 388 C148 378 166 380 176 396 L172 446 C156 458 140 456 130 438 Z M228 388 C212 378 194 380 184 396 L188 446 C204 458 220 456 230 438 Z',
    aliases: ['gluteus_maximus'],
  ),
  _HeatmapSegment(
    code: 'hamstrings',
    pathData:
        'M126 456 C142 460 152 484 150 528 L144 614 C126 610 112 588 112 548 Z M234 456 C218 460 208 484 210 528 L216 614 C234 610 248 588 248 548 Z',
  ),
  _HeatmapSegment(
    code: 'calves',
    pathData:
        'M120 620 C132 624 132 672 122 716 L106 712 C100 676 102 636 120 620 Z M240 620 C228 624 228 672 238 716 L254 712 C260 676 258 636 240 620 Z',
    aliases: ['gastrocnemius', 'soleus'],
  ),
];
