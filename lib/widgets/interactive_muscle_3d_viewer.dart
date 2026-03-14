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
  int _entriesVersion = 0;
  late String _entriesFingerprint;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _entriesFingerprint = _buildEntriesFingerprint(widget.entries);
    _ensureModelAssetReady();
  }

  @override
  void didUpdateWidget(covariant InteractiveMuscle3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFingerprint = _buildEntriesFingerprint(widget.entries);
    if (nextFingerprint == _entriesFingerprint) {
      return;
    }
    _entriesFingerprint = nextFingerprint;
    _entriesVersion += 1;
    _modelReady = false;
    _showFallback = false;
    if (_assetReady) {
      _startFallbackWatchdog();
    }
  }

  @override
  void deactivate() {
    // 화면 전환 시 watchdog 타이머가 백그라운드에서 남지 않도록 정리한다.
    _fallbackTimer?.cancel();
    super.deactivate();
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
                key: ValueKey(
                  'muscle-3d-$statusSignature-${_entriesFingerprint.hashCode}-$_entriesVersion-$_retryVersion',
                ),
                src: _modelAssetPath,
                alt: '3D Human Muscular System',
                ar: false,
                loading: mv.Loading.eager,
                reveal: mv.Reveal.auto,
                backgroundColor: Colors.transparent,
                cameraControls: widget.interactive,
                disableZoom: !widget.interactive,
                disablePan: !widget.interactive,
                touchAction: widget.interactive
                    ? mv.TouchAction.none
                    : mv.TouchAction.panY,
                autoRotate: widget.autoRotate,
                interactionPrompt: widget.interactive
                    ? mv.InteractionPrompt.auto
                    : mv.InteractionPrompt.none,
                interactionPromptStyle: mv.InteractionPromptStyle.basic,
                fieldOfView: '45deg',
                cameraOrbit: '0deg 75deg 1.2m',
                cameraTarget: '0m 0.9m 0m',
                minCameraOrbit: 'auto auto 1.0m',
                maxCameraOrbit: 'auto auto 2.8m',
                minFieldOfView: '35deg',
                maxFieldOfView: '60deg',
                exposure: 1.2,
                shadowIntensity: 2.0,
                shadowSoftness: 0.5,
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

  String _buildEntriesFingerprint(List<MuscleHeatmapEntry> entries) {
    final normalized = entries.map((entry) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      final score = entry.conditionScore.toStringAsFixed(3);
      final display = entry.displayScore;
      final trainedAt = entry.lastTrainedAt?.millisecondsSinceEpoch ?? 0;
      return '$code:${entry.status.rawValue}:$score:$display:$trainedAt';
    }).toList()
      ..sort();
    return normalized.join('|');
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
    pectoralis_major: 'Material_Chest',
    pectoralis_minor: 'Material_Chest',
    serratus_anterior: 'Material_Chest',
    front_deltoid: 'Material_Shoulders',
    anterior_deltoid: 'Material_Shoulders',
    lateral_deltoid: 'Material_Shoulders',
    rear_deltoid: 'Material_Shoulders',
    triceps: 'Material_UpperArms',
    biceps: 'Material_UpperArms',
    brachialis: 'Material_UpperArms',
    brachioradialis: 'Material_UpperArms',
    forearm_flexor: 'Material_UpperArms',
    forearm_extensor: 'Material_UpperArms',
    rectus_abdominis: 'Material_Abs',
    obliques: 'Material_Obliques',
    quadriceps: 'Material_Quads',
    vastus_lateralis: 'Material_Quads',
    vastus_medialis: 'Material_Quads',
    vastus_intermedius: 'Material_Quads',
    rectus_femoris: 'Material_Quads',
    adductors: 'Material_Quads',
    abductors: 'Material_Quads',
    hip_flexor: 'Material_Quads',
    hamstrings: 'Material_Glutes',
    biceps_femoris: 'Material_Glutes',
    semitendinosus: 'Material_Glutes',
    semimembranosus: 'Material_Glutes',
    glutes: 'Material_Glutes',
    gluteus_maximus: 'Material_Glutes',
    gluteus_medius: 'Material_Glutes',
    gluteus_minimus: 'Material_Glutes',
    calves: 'Material_Calves',
    gastrocnemius: 'Material_Calves',
    soleus: 'Material_Calves',
    tibialis_anterior: 'Material_Calves',
    latissimus: 'Material_Lats',
    latissimus_dorsi: 'Material_Lats',
    latissimus_lower: 'Material_Lats',
    latissimus_upper: 'Material_Lats',
    teres_major: 'Material_Lats',
    infraspinatus: 'Material_Lats',
    supraspinatus: 'Material_Lats',
    teres_minor: 'Material_Lats',
    subscapularis: 'Material_Lats',
    erector_spinae: 'Material_LowerBack',
    lower_back: 'Material_LowerBack',
    lumbar: 'Material_LowerBack',
    trapezius: 'Material_Neck',
    neck: 'Material_Neck',
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
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
  'upper_abs': 'rectus_abdominis',
  'lower_abs': 'rectus_abdominis',
  'core': 'rectus_abdominis',
  'pectoralis_major': 'chest',
  'pectoralis_minor': 'chest',
  'pecs': 'chest',
  'chest_major': 'chest',
  'anterior_deltoid': 'front_deltoid',
  'front_delts': 'front_deltoid',
  'side_deltoid': 'lateral_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'rear_delts': 'rear_deltoid',
  'biceps_brachii': 'biceps',
  'brachioradialis': 'forearm_extensor',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'quads': 'quadriceps',
  'rectus_femoris': 'quadriceps',
  'vastus_lateralis': 'quadriceps',
  'vastus_medialis': 'quadriceps',
  'vastus_intermedius': 'quadriceps',
  'hamstring': 'hamstrings',
  'biceps_femoris': 'hamstrings',
  'semitendinosus': 'hamstrings',
  'semimembranosus': 'hamstrings',
  'adductor_longus': 'adductors',
  'adductor_brevis': 'adductors',
  'adductor_magnus': 'adductors',
  'hip_adductors': 'adductors',
  'hip_abductors': 'abductors',
  'abductor': 'abductors',
  'gluteus_maximus': 'glutes',
  'gluteus_medius': 'glutes',
  'gluteus_minimus': 'glutes',
  'glute_medius': 'abductors',
  'lats': 'latissimus',
  'latissimus_dorsi': 'latissimus',
  'latissimus_lower': 'latissimus',
  'latissimus_upper': 'latissimus',
  'teres_major': 'latissimus',
  'spinal_erectors': 'erector_spinae',
  'erectors': 'erector_spinae',
  'lumbar': 'lower_back',
  'upper_trap': 'trapezius',
  'middle_trap': 'trapezius',
  'lower_trap': 'trapezius',
  'cervical': 'neck',
  'gastrocnemius': 'calves',
  'gastrocnemius_medial': 'calves',
  'gastrocnemius_lateral': 'calves',
  'calf': 'calves',
  'shin': 'tibialis_anterior',
  'tibialis': 'tibialis_anterior',
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
