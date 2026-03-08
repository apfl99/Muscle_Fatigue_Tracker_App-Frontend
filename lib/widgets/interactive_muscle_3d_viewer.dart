import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart' as mv;

import '../features/heatmap/model/heatmap_models.dart';
import '../theme/app_theme.dart';

class InteractiveMuscle3DViewer extends StatefulWidget {
  const InteractiveMuscle3DViewer({
    super.key,
    required this.entries,
    this.borderRadius = 20,
    this.exposeBackgroundKey = false,
    this.interactive = true,
    this.autoRotate = true,
    this.showHotspots = true,
    this.onMuscleTap,
  });

  final List<MuscleHeatmapEntry> entries;
  final double borderRadius;
  final bool exposeBackgroundKey;
  final bool interactive;
  final bool autoRotate;
  final bool showHotspots;
  final ValueChanged<String>? onMuscleTap;

  @override
  State<InteractiveMuscle3DViewer> createState() =>
      _InteractiveMuscle3DViewerState();
}

class _InteractiveMuscle3DViewerState extends State<InteractiveMuscle3DViewer> {
  static const String _modelAssetPath =
      'assets/models/human_muscular_system_segmented.glb';
  static const Duration _fallbackTimeout = Duration(seconds: 8);
  static const bool _e2eStub3D = bool.fromEnvironment(
    'MUSCLECARE_E2E_STUB_3D',
    defaultValue: false,
  );

  bool _assetReady = false;
  bool _assetFailed = false;
  bool _modelReady = false;
  bool _showFallback = false;
  int _retryVersion = 0;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _ensureModelAssetReady();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureModelAssetReady() async {
    try {
      await rootBundle.load(_modelAssetPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _assetReady = true;
        _assetFailed = false;
        _showFallback = false;
      });
      _startFallbackWatchdog();
    } catch (error) {
      debugPrint('[InteractiveMuscle3DViewer] 3D 모델 에셋 로드 실패: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _assetReady = false;
        _assetFailed = true;
        _showFallback = true;
      });
    }
  }

  void _startFallbackWatchdog() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(_fallbackTimeout, () {
      if (!mounted || _modelReady) {
        return;
      }
      debugPrint('[InteractiveMuscle3DViewer] 모델 로드 지연으로 fallback 표시');
      setState(() {
        _showFallback = true;
      });
    });
  }

  void _retryModelLoad() {
    setState(() {
      _retryVersion += 1;
      _modelReady = false;
      _showFallback = false;
      _assetFailed = false;
      _assetReady = true;
    });
    _startFallbackWatchdog();
  }

  @override
  Widget build(BuildContext context) {
    final averageScore = _averageScore(widget.entries);
    final auraColor = _colorForScore(averageScore);
    final statusByMuscle = _resolveStatusByMuscleCode(widget.entries);
    final statusSignature = _buildStatusSignature(statusByMuscle);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            key: widget.exposeBackgroundKey
                ? const Key('viewer_dynamic_background')
                : null,
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.95,
                colors: [
                  auraColor.withValues(alpha: 0.30),
                  auraColor.withValues(alpha: 0.08),
                  AppTheme.darkBackground,
                ],
                stops: const [0.0, 0.44, 1.0],
              ),
            ),
          ),
          if (_e2eStub3D) _buildE2EStubLayer(statusByMuscle),
          if (_assetReady && !_e2eStub3D)
            SizedBox.expand(
              child: mv.ModelViewer(
                key: ValueKey('muscle-3d-$statusSignature-$_retryVersion'),
                src: _modelAssetPath,
                alt: '3D Human Muscular System',
                ar: false,
                loading: mv.Loading.eager,
                reveal: mv.Reveal.auto,
                backgroundColor: Colors.transparent,
                cameraControls: true,
                disableZoom: false,
                disablePan: false,
                touchAction: widget.interactive
                    ? mv.TouchAction.none
                    : mv.TouchAction.panY,
                autoRotate: false,
                interactionPrompt: widget.interactive
                    ? mv.InteractionPrompt.auto
                    : mv.InteractionPrompt.none,
                interactionPromptStyle: mv.InteractionPromptStyle.basic,
                cameraOrbit: '0deg 90deg 2.8m',
                cameraTarget: '0m 1.05m 0m',
                minCameraOrbit: 'auto 20deg 2.0m',
                maxCameraOrbit: 'auto 165deg 4.5m',
                exposure: 1.08,
                shadowIntensity: 0.58,
                shadowSoftness: 0.62,
                innerModelViewerHtml: widget.showHotspots
                    ? _buildHotspotsHtml(statusByMuscle)
                    : null,
                relatedCss:
                    _viewerCss + (widget.showHotspots ? _hotspotCss : ''),
                relatedJs: _buildMeshTintScript(statusByMuscle),
                javascriptChannels: <mv.JavascriptChannel>{
                  mv.JavascriptChannel(
                    'MuscleTap',
                    onMessageReceived: (message) {
                      final tappedMuscleCode =
                          _normalizeMuscleCode(message.message);
                      widget.onMuscleTap?.call(tappedMuscleCode);
                    },
                  ),
                  mv.JavascriptChannel(
                    'ModelLog',
                    onMessageReceived: (message) {
                      debugPrint(
                        '[InteractiveMuscle3DViewer][js] ${message.message}',
                      );
                    },
                  ),
                  mv.JavascriptChannel(
                    'ModelReady',
                    onMessageReceived: (message) {
                      if (!mounted) {
                        return;
                      }
                      final type = message.message.trim().toLowerCase();
                      if (type == 'ready') {
                        _fallbackTimer?.cancel();
                        setState(() {
                          _modelReady = true;
                          _showFallback = false;
                        });
                      } else if (type == 'error') {
                        debugPrint(
                          '[InteractiveMuscle3DViewer] JS 런타임에서 모델 오류 수신',
                        );
                        setState(() {
                          _modelReady = false;
                          _showFallback = true;
                        });
                      }
                    },
                  ),
                },
              ),
            ),
          if (!_assetReady && !_assetFailed && !_e2eStub3D)
            const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryGreen,
              ),
            ),
          if (_showFallback && !_e2eStub3D) _buildFallbackLayer(),
          if (_assetReady && !_modelReady && !_showFallback && !_e2eStub3D)
            _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGreen),
            SizedBox(height: 12),
            Text(
              '3D 해부학 모델을 불러오는 중입니다...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildE2EStubLayer(Map<String, HeatmapStatus> statusByMuscle) {
    final primaryTarget = _pickPrimaryTapTarget(statusByMuscle);
    final primaryStatus =
        statusByMuscle[primaryTarget] ?? HeatmapStatus.unknown;
    final primaryColor = _colorForStatus(primaryStatus);
    return Positioned.fill(
      child: GestureDetector(
        key: const Key('e2e_stub_muscle_map'),
        behavior: HitTestBehavior.deferToChild,
        onTap: () => widget.onMuscleTap?.call(primaryTarget),
        child: Center(
          child: Container(
            width: 210,
            height: 280,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(110),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  primaryColor.withValues(alpha: 0.45),
                  const Color(0xFF27324B),
                ],
              ),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.72),
                width: 1.2,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.accessibility_new_rounded,
                color: Colors.white70,
                size: 84,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackLayer() {
    return ColoredBox(
      color: const Color(0xB30A0E27),
      child: Center(
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2238),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.accessibility_new_rounded,
                color: Color(0xFF9CA7BC),
                size: 54,
              ),
              const SizedBox(height: 10),
              const Text(
                '기본 회색 인체 맵으로 전환되었습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retryModelLoad,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                ),
                child: const Text('3D 다시 로드'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, HeatmapStatus> _resolveStatusByMuscleCode(
    List<MuscleHeatmapEntry> entries,
  ) {
    final statusByMuscle = <String, HeatmapStatus>{};
    for (final entry in entries) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      final previous = statusByMuscle[code];
      if (previous == null ||
          _statusPriority(entry.status) > _statusPriority(previous)) {
        statusByMuscle[code] = entry.status;
      }
    }
    return statusByMuscle;
  }

  String _buildStatusSignature(Map<String, HeatmapStatus> statusByMuscle) {
    final ordered = statusByMuscle.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ordered
        .map((entry) => '${entry.key}:${entry.value.rawValue}')
        .join('|');
  }

  String _pickPrimaryTapTarget(Map<String, HeatmapStatus> statusByMuscle) {
    const preferredOrder = <String>[
      'chest',
      'quadriceps',
      'latissimus',
      'hamstrings',
      'glutes',
      'front_deltoid',
      'trapezius',
    ];
    for (final code in preferredOrder) {
      if (statusByMuscle.containsKey(code)) {
        return code;
      }
    }
    return 'chest';
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

  String _buildHotspotsHtml(Map<String, HeatmapStatus> statusByMuscle) {
    final buffer = StringBuffer();
    for (final hotspot in _hotspots) {
      final normalizedCode = _normalizeMuscleCode(hotspot.code);
      final status = statusByMuscle[normalizedCode] ?? HeatmapStatus.unknown;
      final color = _colorForStatus(status);
      final alpha = _alphaForStatus(status);
      final cssColor = _toCssRgba(color, alpha);
      buffer.writeln(
        '<button class="muscle-hotspot"'
        ' slot="hotspot-${hotspot.code}"'
        ' data-position="${hotspot.position}"'
        ' data-normal="${hotspot.normal}"'
        ' data-visibility-attribute="visible"'
        ' title="${hotspot.code}"'
        ' style="background:$cssColor; box-shadow: 0 0 14px $cssColor;"'
        ' onclick="if (typeof MuscleTap !== \'undefined\') { MuscleTap.postMessage(\'$normalizedCode\'); }"></button>',
      );
    }
    return buffer.toString();
  }

  String _buildMeshTintScript(Map<String, HeatmapStatus> statusByMuscle) {
    final statusJson =
        jsonEncode(statusByMuscle.map((k, v) => MapEntry(k, v.rawValue)));
    return '''
(() => {
  const statusByMuscle = $statusJson;

  const COLOR_GREEN = [0.0, 0.90, 0.46, 1.0];
  const COLOR_YELLOW = [1.0, 0.65, 0.15, 1.0];
  const COLOR_RED = [0.89, 0.22, 0.20, 1.0];
  const COLOR_UNKNOWN = [0.38, 0.44, 0.56, 0.85];

  function colorForStatus(raw) {
    const v = String(raw || '').toLowerCase();
    if (v === 'green') return COLOR_GREEN;
    if (v === 'yellow') return COLOR_YELLOW;
    if (v === 'red') return COLOR_RED;
    return COLOR_UNKNOWN;
  }

  const materialNameByMuscle = {
    chest: 'Material_Chest',
    quadriceps: 'Material_Quads',
    glutes: 'Material_Glutes',
    calves: 'Material_Calves',
    latissimus: 'Material_Lats',
    erector_spinae: 'Material_LowerBack',
    rectus_abdominis: 'Material_Abs',
    obliques: 'Material_Obliques',
    lateral_deltoid: 'Material_Shoulders',
    biceps: 'Material_UpperArms',
    trapezius: 'Material_Neck',
  };

  function applyTint(modelViewer) {
    try {
      function log(msg) {
        if (typeof ModelLog !== 'undefined') {
          ModelLog.postMessage(String(msg));
        }
      }

      function postReady(type) {
        if (typeof ModelReady !== 'undefined') {
          ModelReady.postMessage(type);
        }
      }

      if (!modelViewer || !modelViewer.model || !modelViewer.model.materials) {
        log('model/materials not ready');
        return;
      }

      const materials = [];
      for (let i = 0; i < modelViewer.model.materials.length; i++) {
        materials.push(modelViewer.model.materials[i]);
      }
      log('materials=' + materials.length);

      let applied = 0;
      for (const muscleId of Object.keys(materialNameByMuscle)) {
        const matName = materialNameByMuscle[muscleId];
        let material = null;
        for (const m of materials) {
          if (m && String(m.name || '') === matName) {
            material = m;
            break;
          }
        }
        if (!material) continue;

        const rawStatus = statusByMuscle[muscleId];
        const color = colorForStatus(rawStatus);
        if (material.pbrMetallicRoughness && material.pbrMetallicRoughness.setBaseColorFactor) {
          material.pbrMetallicRoughness.setBaseColorFactor(color);
          applied += 1;
        }
      }

      log('tint_applied=' + applied);
      postReady('ready');
    } catch (e) {
      if (typeof ModelLog !== 'undefined') {
        ModelLog.postMessage('applyTint error: ' + e);
      }
      if (typeof ModelReady !== 'undefined') {
        ModelReady.postMessage('error');
      }
    }
  }

  const modelViewer = document.querySelector('model-viewer');
  if (!modelViewer) {
    if (typeof ModelLog !== 'undefined') {
      ModelLog.postMessage('model-viewer not found');
    }
    return;
  }

  modelViewer.addEventListener('load', () => applyTint(modelViewer));
  modelViewer.addEventListener('error', () => {
    if (typeof ModelLog !== 'undefined') {
      ModelLog.postMessage('model-viewer error event');
    }
    if (typeof ModelReady !== 'undefined') ModelReady.postMessage('error');
  });
  setTimeout(() => applyTint(modelViewer), 900);
})();
''';
  }

  double _averageScore(List<MuscleHeatmapEntry> entries) {
    if (entries.isEmpty) {
      return 1.0;
    }
    final values = entries.map((entry) {
      if (entry.conditionScore > 0) {
        return entry.conditionScore.clamp(1.0, 3.0);
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
        const Color(0xFFE53935);
  }

  Color _colorForStatus(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return const Color(0xFFE53935);
      case HeatmapStatus.yellow:
        return const Color(0xFFFFA726);
      case HeatmapStatus.green:
        return AppTheme.primaryGreen;
      case HeatmapStatus.unknown:
        return const Color(0xFF60718F);
    }
  }

  double _alphaForStatus(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return 0.94;
      case HeatmapStatus.yellow:
        return 0.88;
      case HeatmapStatus.green:
        return 0.80;
      case HeatmapStatus.unknown:
        return 0.52;
    }
  }

  String _toCssRgba(Color color, double alpha) {
    return 'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()}, ${alpha.toStringAsFixed(2)})';
  }

  String _normalizeMuscleCode(String rawCode) {
    final normalized = rawCode.trim().toLowerCase();
    return _muscleAliases[normalized] ?? normalized;
  }
}

class _ModelHotspot {
  const _ModelHotspot({
    required this.code,
    required this.position,
    required this.normal,
  });

  final String code;
  final String position;
  final String normal;
}

const List<_ModelHotspot> _hotspots = [
  _ModelHotspot(
    code: 'chest',
    position: '0m 1.35m 0.18m',
    normal: '0m 0m 1m',
  ),
  _ModelHotspot(
    code: 'front_deltoid',
    position: '-0.24m 1.42m 0.12m',
    normal: '-0.4m 0.1m 1m',
  ),
  _ModelHotspot(
    code: 'lateral_deltoid',
    position: '0.24m 1.42m 0.12m',
    normal: '0.4m 0.1m 1m',
  ),
  _ModelHotspot(
    code: 'rectus_abdominis',
    position: '0m 1.12m 0.16m',
    normal: '0m 0m 1m',
  ),
  _ModelHotspot(
    code: 'obliques',
    position: '-0.16m 1.08m 0.14m',
    normal: '-0.35m 0m 1m',
  ),
  _ModelHotspot(
    code: 'quadriceps',
    position: '0.10m 0.72m 0.12m',
    normal: '0.1m -0.1m 1m',
  ),
  _ModelHotspot(
    code: 'calves',
    position: '0.08m 0.32m 0.10m',
    normal: '0.1m 0m 1m',
  ),
  _ModelHotspot(
    code: 'trapezius',
    position: '0m 1.50m -0.16m',
    normal: '0m 0.1m -1m',
  ),
  _ModelHotspot(
    code: 'latissimus',
    position: '0.20m 1.22m -0.12m',
    normal: '0.4m 0m -1m',
  ),
  _ModelHotspot(
    code: 'erector_spinae',
    position: '0m 1.02m -0.13m',
    normal: '0m 0m -1m',
  ),
  _ModelHotspot(
    code: 'glutes',
    position: '0.12m 0.86m -0.14m',
    normal: '0.2m -0.1m -1m',
  ),
  _ModelHotspot(
    code: 'hamstrings',
    position: '0.10m 0.62m -0.10m',
    normal: '0.15m -0.2m -1m',
  ),
];

const Map<String, String> _muscleAliases = {
  'front_delts': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'rear_delts': 'rear_deltoid',
  'quads': 'quadriceps',
  'lats': 'latissimus',
  'abs': 'rectus_abdominis',
  'gastrocnemius': 'calves',
  'soleus': 'calves',
  'latissimus_dorsi': 'latissimus',
};

const String _hotspotCss = '''
.muscle-hotspot {
  width: 20px;
  height: 20px;
  border-radius: 999px;
  border: none;
  cursor: pointer;
  opacity: 0.9;
  transition: transform 180ms ease, opacity 800ms ease, background-color 800ms ease, box-shadow 800ms ease;
}

.muscle-hotspot:hover {
  transform: scale(1.18);
  opacity: 1;
}

.muscle-hotspot:active {
  transform: scale(0.96);
}
''';

const String _viewerCss = '''
html, body {
  margin: 0;
  padding: 0;
  background: transparent;
}
model-viewer {
  width: 100%;
  height: 100%;
  background: transparent;
}
''';
