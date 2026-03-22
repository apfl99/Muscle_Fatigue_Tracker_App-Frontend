import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart' as mv;
import 'package:webview_flutter/webview_flutter.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../theme/app_theme.dart';

/// 3D 뷰어의 런타임 JS payload를 외부에서 주입/동기화하기 위한 컨트롤러.
class InteractiveMuscle3DController extends ChangeNotifier {
  String _runtimePayloadJson = '';

  String get runtimePayloadJson => _runtimePayloadJson;

  void setRuntimePayloadJson(String payloadJson) {
    if (_runtimePayloadJson == payloadJson) {
      return;
    }
    _runtimePayloadJson = payloadJson;
    notifyListeners();
  }

  void clear() {
    if (_runtimePayloadJson.isEmpty) {
      return;
    }
    _runtimePayloadJson = '';
    notifyListeners();
  }
}

class InteractiveMuscle3DViewer extends StatefulWidget {
  const InteractiveMuscle3DViewer({
    super.key,
    required this.entries,
    this.borderRadius = 20,
    this.exposeBackgroundKey = false,
    this.interactive = true,
    this.autoRotate = false,
    this.showHotspots = false,
    this.highlightedMuscleCode,
    this.onMuscleTap,
    this.onFallbackTo2D,
    this.mockModelSrc,
    this.controller,
  });

  final List<MuscleHeatmapEntry> entries;
  final double borderRadius;
  final bool exposeBackgroundKey;
  final bool interactive;
  final bool autoRotate;
  final bool showHotspots;
  final String? highlightedMuscleCode;
  final ValueChanged<String>? onMuscleTap;
  final VoidCallback? onFallbackTo2D;
  final String? mockModelSrc;
  final InteractiveMuscle3DController? controller;

  @override
  State<InteractiveMuscle3DViewer> createState() =>
      _InteractiveMuscle3DViewerState();
}

class _InteractiveMuscle3DViewerState extends State<InteractiveMuscle3DViewer> {
  static const String _primaryModelAssetPath =
      'assets/models/human_muscular_system_segmented.glb';
  static const String _defaultMockModelSrc =
      'https://raw.githubusercontent.com/msorkhpar/3d-human-model-vite/main/body.glb';
  static const Duration _fallbackTimeout = Duration(seconds: 10);
  static const bool _e2eStub3D = bool.fromEnvironment(
    'MUSCLECARE_E2E_STUB_3D',
    defaultValue: false,
  );
  static const bool _useMockHeatmapData = bool.fromEnvironment(
    'MUSCLECARE_USE_MOCK_3D_DATA',
    defaultValue: false,
  );

  bool _assetReady = false;
  bool _assetFailed = false;
  bool _modelReady = false;
  bool _showFallback = false;
  bool _usingMockModelSource = false;
  int _retryVersion = 0;
  String _resolvedModelSrc = _defaultMockModelSrc;
  late String _entriesFingerprint;
  Timer? _fallbackTimer;
  Timer? _runtimeUpdateDebounce;
  WebViewController? _webViewController;
  bool _fallbackNotified = false;
  String _runtimePayloadJson = '';
  String _lastAppliedRuntimePayloadJson = '';

  @override
  void initState() {
    super.initState();
    _entriesFingerprint = _buildEntriesFingerprint(
      _effectiveEntries(widget.entries),
    );
    _resolvedModelSrc = widget.mockModelSrc ?? _defaultMockModelSrc;
    widget.controller?.addListener(_handleExternalControllerUpdate);
    _ensureModelSourceReady();
  }

  @override
  void didUpdateWidget(covariant InteractiveMuscle3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleExternalControllerUpdate);
      widget.controller?.addListener(_handleExternalControllerUpdate);
    }

    if (widget.mockModelSrc != oldWidget.mockModelSrc &&
        !_assetReady &&
        !_assetFailed) {
      _resolvedModelSrc = widget.mockModelSrc ?? _defaultMockModelSrc;
      _ensureModelSourceReady();
    }

    final nextFingerprint = _buildEntriesFingerprint(
      _effectiveEntries(widget.entries),
    );
    final nextHighlighted = _normalizeMuscleCode(widget.highlightedMuscleCode ?? '');
    final previousHighlighted = _normalizeMuscleCode(
      oldWidget.highlightedMuscleCode ?? '',
    );
    if (nextFingerprint != _entriesFingerprint ||
        nextHighlighted != previousHighlighted) {
      _entriesFingerprint = nextFingerprint;
    }
  }

  @override
  void deactivate() {
    // 화면 전환 시 watchdog 타이머가 백그라운드에서 남지 않도록 정리한다.
    _fallbackTimer?.cancel();
    _runtimeUpdateDebounce?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _runtimeUpdateDebounce?.cancel();
    widget.controller?.removeListener(_handleExternalControllerUpdate);
    super.dispose();
  }

  Future<void> _ensureModelSourceReady() async {
    try {
      await rootBundle.load(_primaryModelAssetPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _assetReady = true;
        _assetFailed = false;
        _showFallback = false;
        _usingMockModelSource = false;
        _resolvedModelSrc = _primaryModelAssetPath;
        _modelReady = false;
        _fallbackNotified = false;
        _lastAppliedRuntimePayloadJson = '';
      });
      _startFallbackWatchdog();
    } catch (error) {
      debugPrint(
        '[InteractiveMuscle3DViewer] 로컬 3D 모델 에셋 부재 → mock URL 사용: $error',
      );
      if (!mounted) {
        return;
      }
      final fallbackSrc = widget.mockModelSrc ?? _defaultMockModelSrc;
      if (fallbackSrc.trim().isEmpty) {
        setState(() {
          _assetReady = false;
          _assetFailed = true;
          _showFallback = true;
          _usingMockModelSource = false;
        });
        _notifyFallbackTo2D();
        return;
      }
      setState(() {
        _assetReady = true;
        _assetFailed = false;
        _showFallback = false;
        _usingMockModelSource = true;
        _resolvedModelSrc = fallbackSrc;
        _modelReady = false;
        _fallbackNotified = false;
        _lastAppliedRuntimePayloadJson = '';
      });
      _startFallbackWatchdog();
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
      _notifyFallbackTo2D();
    });
  }

  void _retryModelLoad() {
    setState(() {
      _retryVersion += 1;
      _modelReady = false;
      _showFallback = false;
      _assetFailed = false;
      _assetReady = false;
      _fallbackNotified = false;
      _lastAppliedRuntimePayloadJson = '';
    });
    _webViewController = null;
    _ensureModelSourceReady();
  }

  void _notifyFallbackTo2D() {
    if (_fallbackNotified) {
      return;
    }
    _fallbackNotified = true;
    widget.onFallbackTo2D?.call();
  }

  List<MuscleHeatmapEntry> _effectiveEntries(List<MuscleHeatmapEntry> entries) {
    if (entries.isNotEmpty || !_useMockHeatmapData) {
      return entries;
    }
    return _mockEntries;
  }

  void _handleExternalControllerUpdate() {
    final payloadJson = widget.controller?.runtimePayloadJson ?? '';
    if (payloadJson.isEmpty || payloadJson == _runtimePayloadJson) {
      return;
    }
    _runtimePayloadJson = payloadJson;
    _queueRuntimeUpdate(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEntries = _effectiveEntries(widget.entries);
    final averageScore = _averageScore(effectiveEntries);
    final auraColor = _colorForScore(averageScore);
    final statusByMuscle = _resolveStatusByMuscleCode(effectiveEntries);
    final severityByMuscle = _resolveSeverityByMuscleCode(effectiveEntries);
    final highlightedMuscleCode = _normalizeMuscleCode(
      widget.highlightedMuscleCode ?? '',
    );
    final runtimePayloadJson = _buildRuntimePayloadJson(
      statusByMuscle: statusByMuscle,
      severityByMuscle: severityByMuscle,
      highlightedMuscleCode: highlightedMuscleCode,
    );
    if (_runtimePayloadJson != runtimePayloadJson) {
      _runtimePayloadJson = runtimePayloadJson;
      widget.controller?.setRuntimePayloadJson(runtimePayloadJson);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _queueRuntimeUpdate();
      });
    }

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
                  'muscle-3d-${_resolvedModelSrc.hashCode}-$_retryVersion',
                ),
                src: _resolvedModelSrc,

                // 1. 인터랙션 제어: 회전만 허용, 줌/이동 완벽 차단
                cameraControls: widget.interactive,
                disableZoom: true,
                disablePan: true,
                disableTap: true,
                touchAction: mv.TouchAction.none,

                // 2. 오토 프레이밍: 수동 거리 조절(m, %)을 전부 폐기하고 자동 핏(Fit) 적용
                cameraOrbit: '0deg 90deg auto',
                cameraTarget: 'auto auto auto',

                // 3. 다크 테마 + 경계 분리 강화 조명
                environmentImage: 'neutral',
                exposure: 0.92,
                shadowIntensity: 0.95,
                shadowSoftness: 0.20,
                orbitSensitivity: 1,

                backgroundColor: Colors.transparent,
                alt: '3D Human Muscular System',
                ar: false,
                loading: mv.Loading.eager,
                reveal: mv.Reveal.auto,
                autoRotate: widget.autoRotate,
                innerModelViewerHtml: widget.showHotspots
                    ? _buildHotspotsHtml(statusByMuscle)
                    : null,
                relatedCss:
                    _viewerCss + (widget.showHotspots ? _hotspotCss : ''),
                relatedJs: _buildMeshTintScript(
                  initialPayloadJson: runtimePayloadJson,
                ),
                debugLogging: false,
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  _queueRuntimeUpdate();
                },
                javascriptChannels: <mv.JavascriptChannel>{
                  mv.JavascriptChannel(
                    'MuscleTap',
                    onMessageReceived: (message) {
                      final tappedMuscleCode = _extractMuscleCodeFromTapMessage(
                        message.message,
                      );
                      if (tappedMuscleCode.isEmpty) {
                        return;
                      }
                      HapticFeedback.lightImpact();
                      widget.onMuscleTap?.call(tappedMuscleCode);
                    },
                  ),
                  mv.JavascriptChannel(
                    'ModelLog',
                    onMessageReceived: (message) {
                      if (!kDebugMode) {
                        return;
                      }
                      final raw = message.message.trim();
                      final lower = raw.toLowerCase();
                      // 성공 경로의 반복 로그(materials/tint_applied)는 제외하고
                      // 실제 진단에 필요한 실패성 로그만 남긴다.
                      if (lower.contains('error') ||
                          lower.contains('not ready') ||
                          lower.contains('failed')) {
                        debugPrint('[InteractiveMuscle3DViewer][js] $raw');
                      }
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
                        _queueRuntimeUpdate(immediate: true);
                      } else if (type == 'error') {
                        debugPrint(
                          '[InteractiveMuscle3DViewer] JS 런타임에서 모델 오류 수신',
                        );
                        setState(() {
                          _modelReady = false;
                          _showFallback = true;
                        });
                        _notifyFallbackTo2D();
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

  void _queueRuntimeUpdate({bool immediate = false}) {
    if (!_modelReady || _runtimePayloadJson.isEmpty) {
      return;
    }
    if (_runtimePayloadJson == _lastAppliedRuntimePayloadJson) {
      return;
    }
    _runtimeUpdateDebounce?.cancel();
    if (immediate) {
      _pushRuntimeUpdateNow();
      return;
    }
    _runtimeUpdateDebounce = Timer(const Duration(milliseconds: 36), () {
      _pushRuntimeUpdateNow();
    });
  }

  Future<void> _pushRuntimeUpdateNow() async {
    if (!_modelReady || _runtimePayloadJson.isEmpty) {
      return;
    }
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    final payloadEncoded = jsonEncode(_runtimePayloadJson);
    final js = '''
(() => {
  try {
    const payload = JSON.parse($payloadEncoded);
    if (window.__muscleViewerApi &&
        typeof window.__muscleViewerApi.applyRuntimeUpdate === 'function') {
      window.__muscleViewerApi.applyRuntimeUpdate(payload);
    } else if (typeof ModelLog !== 'undefined') {
      ModelLog.postMessage('runtime api not ready');
    }
  } catch (error) {
    if (typeof ModelLog !== 'undefined') {
      ModelLog.postMessage('runtime update failed: ' + error);
    }
  }
})();
''';
    try {
      await controller.runJavaScript(js);
      _lastAppliedRuntimePayloadJson = _runtimePayloadJson;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[InteractiveMuscle3DViewer] 런타임 컬러 주입 실패: $error',
        );
      }
    }
  }

  String _extractMuscleCodeFromTapMessage(String rawMessage) {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (!trimmed.startsWith('{')) {
      return _normalizeMuscleCode(trimmed);
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return '';
      }
      final muscleCode = _normalizeMuscleCode(
        (decoded['muscleCode'] as String?) ?? '',
      );
      if (muscleCode.isNotEmpty) {
        return muscleCode;
      }
      final materialName =
          ((decoded['materialName'] as String?) ?? '').trim().toLowerCase();
      return _normalizeMuscleCode(_muscleByMaterialAlias[materialName] ?? '');
    } catch (_) {
      return '';
    }
  }

  Widget _buildLoadingOverlay() {
    return ColoredBox(
      color: AppTheme.surface1.withValues(alpha: 0.42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryGreen),
            const SizedBox(height: 12),
            Text(
              _usingMockModelSource
                  ? '${'viewer.interactive3d.loading'.tr()} (mock)'
                  : 'viewer.interactive3d.loading'.tr(),
              style: TextStyle(color: AppTheme.textMedium, fontSize: 12),
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
            child: Center(
              child: Icon(
                Icons.accessibility_new_rounded,
                color: AppTheme.textMedium,
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
      color: AppTheme.surface1.withValues(alpha: 0.76),
      child: Center(
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            color: AppTheme.surface2,
            borderRadius: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.accessibility_new_rounded,
                color: AppTheme.primaryGreen,
                size: 54,
              ),
              const SizedBox(height: 10),
              Text(
                'offline.viewerFallback2D'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMedium,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retryModelLoad,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textHigh,
                  side: BorderSide(color: AppTheme.borderSubtle),
                ),
                child: Text('viewer.interactive3d.retry'.tr()),
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

  Map<String, double> _resolveSeverityByMuscleCode(
    List<MuscleHeatmapEntry> entries,
  ) {
    final severityByMuscle = <String, double>{};
    for (final entry in entries) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      if (code.isEmpty) {
        continue;
      }
      final severity = _severityFromEntry(entry);
      final previous = severityByMuscle[code];
      if (previous == null || severity > previous) {
        severityByMuscle[code] = severity;
      }
    }
    return severityByMuscle;
  }

  double _severityFromEntry(MuscleHeatmapEntry entry) {
    if (entry.conditionScore > 0) {
      final normalized = ((entry.conditionScore.clamp(1.0, 3.0) - 1.0) / 2.0);
      return normalized.clamp(0.0, 1.0);
    }
    switch (entry.status) {
      case HeatmapStatus.red:
        return 1.0;
      case HeatmapStatus.yellow:
        return 0.62;
      case HeatmapStatus.green:
        return 0.16;
      case HeatmapStatus.unknown:
        return 0.0;
    }
  }

  String _buildRuntimePayloadJson({
    required Map<String, HeatmapStatus> statusByMuscle,
    required Map<String, double> severityByMuscle,
    required String highlightedMuscleCode,
  }) {
    final payload = <String, dynamic>{
      'statusByMuscle': statusByMuscle.map(
        (key, value) => MapEntry(key, value.rawValue),
      ),
      'severityByMuscle': severityByMuscle.map(
        (key, value) => MapEntry(key, double.parse(value.toStringAsFixed(4))),
      ),
      'highlightedMuscleCode': highlightedMuscleCode,
    };
    return jsonEncode(payload);
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

  String _buildMeshTintScript({
    required String initialPayloadJson,
  }) {
    final initialPayloadLiteral = jsonEncode(initialPayloadJson);
    return '''
(() => {
  const INITIAL_PAYLOAD_TEXT = $initialPayloadLiteral;
  const COLOR_NEON_GREEN = [0.0, 0.9608, 0.5412, 1.0];  // #00F58A
  const COLOR_RED = [0.95, 0.18, 0.16, 1.0];
  const COLOR_UNKNOWN = [0.28, 0.33, 0.43, 0.90];

  const materialNameByMuscle = {
    chest: 'Material_Chest',
    pectoralis_major: 'Material_Chest',
    pectoralis_minor: 'Material_Chest',
    serratus_anterior: 'Material_Chest',
    shoulders: 'Material_Shoulders',
    front_deltoid: 'Material_Shoulders',
    anterior_deltoid: 'Material_Shoulders',
    lateral_deltoid: 'Material_Shoulders',
    rear_deltoid: 'Material_Shoulders',
    upper_arms: 'Material_UpperArms',
    triceps: 'Material_UpperArms',
    biceps: 'Material_UpperArms',
    brachialis: 'Material_UpperArms',
    brachioradialis: 'Material_UpperArms',
    forearm_flexor: 'Material_UpperArms',
    forearm_extensor: 'Material_UpperArms',
    rectus_abdominis: 'Material_Abs',
    obliques: 'Material_Obliques',
    quads: 'Material_Quads',
    quadriceps: 'Material_Quads',
    vastus_lateralis: 'Material_Quads',
    vastus_medialis: 'Material_Quads',
    vastus_intermedius: 'Material_Quads',
    rectus_femoris: 'Material_Quads',
    adductors: 'Material_Quads',
    abductors: 'Material_Quads',
    hip_flexor: 'Material_Quads',
    posterior_chain: 'Material_Glutes',
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
    back: 'Material_Lats',
    lats: 'Material_Lats',
    latissimus: 'Material_Lats',
    latissimus_dorsi: 'Material_Lats',
    latissimus_lower: 'Material_Lats',
    latissimus_upper: 'Material_Lats',
    teres_major: 'Material_Lats',
    infraspinatus: 'Material_Lats',
    supraspinatus: 'Material_Lats',
    teres_minor: 'Material_Lats',
    subscapularis: 'Material_Lats',
    lower_posterior: 'Material_LowerBack',
    erector_spinae: 'Material_LowerBack',
    lower_back: 'Material_LowerBack',
    lumbar: 'Material_LowerBack',
    upper_posterior: 'Material_Neck',
    trapezius: 'Material_Neck',
    neck: 'Material_Neck',
  };

  const muscleByMeshName = {
    '05_chest': 'chest',
    '06_abdomen': 'rectus_abdominis',
    '07_lower_abdomen': 'obliques',
    '04_shoulders': 'front_deltoid',
    '10_upper_arms': 'biceps',
    '12_fore_arms': 'forearm_flexor',
    '15_thighs': 'quadriceps',
    '17_legs': 'hamstrings',
    '22_buttocks': 'glutes',
    '18_ankles': 'calves',
    '20_back': 'latissimus',
    '21_lower_back': 'erector_spinae',
    '03_neck': 'trapezius',
  };

  function log(message) {
    if (typeof ModelLog !== 'undefined') {
      ModelLog.postMessage(String(message));
    }
  }

  function postReady(state) {
    if (typeof ModelReady !== 'undefined') {
      ModelReady.postMessage(state);
    }
  }

  function clamp01(v) {
    if (!Number.isFinite(v)) return 0;
    return Math.min(1.0, Math.max(0.0, v));
  }

  function lerp(a, b, t) {
    return a + (b - a) * t;
  }

  function normalizeCode(raw) {
    return String(raw || '').trim().toLowerCase();
  }

  function gradientColor(severity) {
    const t = clamp01(severity);
    return [
      lerp(COLOR_NEON_GREEN[0], COLOR_RED[0], t),
      lerp(COLOR_NEON_GREEN[1], COLOR_RED[1], t),
      lerp(COLOR_NEON_GREEN[2], COLOR_RED[2], t),
      1.0,
    ];
  }

  const muscleByMaterialName = {};
  for (const muscleCode of Object.keys(materialNameByMuscle)) {
    const materialName = normalizeCode(materialNameByMuscle[muscleCode]);
    if (!materialName) continue;
    if (!Object.prototype.hasOwnProperty.call(muscleByMaterialName, materialName)) {
      muscleByMaterialName[materialName] = normalizeCode(muscleCode);
    }
  }

  const runtimeState = {
    statusByMuscle: {},
    severityByMuscle: {},
    highlightedMuscleCode: '',
  };

  function setRuntimeState(payload) {
    if (!payload || typeof payload !== 'object') {
      return;
    }
    runtimeState.statusByMuscle = payload.statusByMuscle || {};
    runtimeState.severityByMuscle = payload.severityByMuscle || {};
    runtimeState.highlightedMuscleCode = normalizeCode(payload.highlightedMuscleCode || '');
  }

  function highlightedMaterialName() {
    const code = runtimeState.highlightedMuscleCode;
    if (!code) return '';
    return String(materialNameByMuscle[code] || '');
  }

  function buildSeverityByMaterial() {
    const severityByMaterial = {};
    for (const muscleCode of Object.keys(materialNameByMuscle)) {
      const normalized = normalizeCode(muscleCode);
      const rawSeverity = runtimeState.severityByMuscle[normalized];
      if (rawSeverity == null) {
        continue;
      }
      const severity = clamp01(Number(rawSeverity));
      const materialName = String(materialNameByMuscle[muscleCode] || '');
      if (!materialName) {
        continue;
      }
      severityByMaterial[materialName] = Math.max(
        Number(severityByMaterial[materialName] || 0),
        severity,
      );
    }
    return severityByMaterial;
  }

  function applyTint(modelViewer) {
    if (!modelViewer || !modelViewer.model || !modelViewer.model.materials) {
      log('model/materials not ready');
      return false;
    }

    const materials = [];
    for (let i = 0; i < modelViewer.model.materials.length; i++) {
      materials.push(modelViewer.model.materials[i]);
    }
    if (!materials.length) {
      log('materials=0');
      return false;
    }

    const severityByMaterial = buildSeverityByMaterial();
    const focusedMaterialName = highlightedMaterialName();
    let applied = 0;

    for (const material of materials) {
      if (!material) continue;
      const materialName = String(material.name || '');
      const hasSeverity = Object.prototype.hasOwnProperty.call(
        severityByMaterial,
        materialName,
      );
      let color = hasSeverity
          ? gradientColor(severityByMaterial[materialName])
          : COLOR_UNKNOWN;

      const focused = focusedMaterialName && focusedMaterialName === materialName;
      if (focused) {
        color = [
          Math.min(1.0, color[0] * 0.68 + 0.32),
          Math.min(1.0, color[1] * 0.68 + 0.32),
          Math.min(1.0, color[2] * 0.68 + 0.32),
          1.0,
        ];
      }

      if (material.pbrMetallicRoughness) {
        if (material.pbrMetallicRoughness.setBaseColorFactor) {
          material.pbrMetallicRoughness.setBaseColorFactor(color);
        }
        if (material.pbrMetallicRoughness.setMetallicFactor) {
          material.pbrMetallicRoughness.setMetallicFactor(0.04);
        }
        if (material.pbrMetallicRoughness.setRoughnessFactor) {
          material.pbrMetallicRoughness.setRoughnessFactor(0.82);
        }
        applied += 1;
      }
      if (material.setEmissiveFactor) {
        material.setEmissiveFactor(
          focused ? [0.16, 0.16, 0.16] : [0.0, 0.0, 0.0],
        );
      }
      if (material.setEmissiveStrength) {
        material.setEmissiveStrength(focused ? 1.10 : 0.20);
      }
    }

    log('tint_applied=' + applied);
    return true;
  }

  function resolveTap(modelViewer, event) {
    const rect = modelViewer.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    if (x < 0 || y < 0 || x > rect.width || y > rect.height) {
      return null;
    }

    let materialName = '';
    let muscleCode = '';
    let surfaceId = '';

    if (typeof modelViewer.materialFromPoint === 'function') {
      const material = modelViewer.materialFromPoint(x, y);
      if (material) {
        materialName = String(material.name || '');
        const byMaterial = muscleByMaterialName[normalizeCode(materialName)];
        if (byMaterial) {
          muscleCode = byMaterial;
        }
      }
    }

    if (typeof modelViewer.surfaceFromPoint === 'function') {
      const surface = modelViewer.surfaceFromPoint(x, y);
      if (surface) {
        surfaceId = String(surface);
        if (!muscleCode) {
          const lower = normalizeCode(surfaceId);
          for (const meshName of Object.keys(muscleByMeshName)) {
            if (lower.includes(meshName)) {
              muscleCode = muscleByMeshName[meshName];
              break;
            }
          }
        }
      }
    }

    return {
      muscleCode,
      materialName,
      surfaceId,
    };
  }

  function applyAndNotify(modelViewer) {
    try {
      const applied = applyTint(modelViewer);
      if (applied) {
        postReady('ready');
      }
    } catch (error) {
      log('applyTint error: ' + error);
      postReady('error');
    }
  }

  const modelViewer = document.querySelector('model-viewer');
  if (!modelViewer) {
    log('model-viewer not found');
    return;
  }

  if (window.__muscleViewerApi &&
      typeof window.__muscleViewerApi.dispose === 'function') {
    window.__muscleViewerApi.dispose();
  }

  modelViewer.setAttribute('shadow-intensity', '0.95');
  modelViewer.setAttribute('shadow-softness', '0.20');

  let pointerDown = null;
  const onPointerDown = (event) => {
    pointerDown = {
      x: event.clientX,
      y: event.clientY,
      ts: Date.now(),
    };
  };

  const onPointerUp = (event) => {
    if (!pointerDown) {
      return;
    }
    const dx = event.clientX - pointerDown.x;
    const dy = event.clientY - pointerDown.y;
    const moved = Math.sqrt(dx * dx + dy * dy);
    const elapsed = Date.now() - pointerDown.ts;
    pointerDown = null;
    if (moved > 9 || elapsed > 450) {
      return;
    }
    const hit = resolveTap(modelViewer, event);
    if (!hit) {
      return;
    }
    if (!hit.muscleCode && !hit.materialName && !hit.surfaceId) {
      return;
    }
    if (typeof MuscleTap !== 'undefined') {
      MuscleTap.postMessage(JSON.stringify(hit));
    }
  };

  const onLoad = () => applyAndNotify(modelViewer);
  const onError = () => {
    log('model-viewer error event');
    postReady('error');
  };

  modelViewer.addEventListener('load', onLoad);
  modelViewer.addEventListener('error', onError);
  modelViewer.addEventListener('pointerdown', onPointerDown, {passive: true});
  modelViewer.addEventListener('pointerup', onPointerUp, {passive: true});

  window.__muscleViewerApi = {
    applyRuntimeUpdate(payload) {
      try {
        setRuntimeState(payload);
        applyAndNotify(modelViewer);
      } catch (error) {
        log('runtime update failed: ' + error);
      }
    },
    dispose() {
      modelViewer.removeEventListener('load', onLoad);
      modelViewer.removeEventListener('error', onError);
      modelViewer.removeEventListener('pointerdown', onPointerDown);
      modelViewer.removeEventListener('pointerup', onPointerUp);
      delete window.__muscleViewerApi;
    },
  };

  try {
    const payload = JSON.parse(INITIAL_PAYLOAD_TEXT);
    setRuntimeState(payload);
  } catch (error) {
    log('initial payload parse failed: ' + error);
  }

  setTimeout(() => applyAndNotify(modelViewer), 260);
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

const Map<String, String> _muscleByMaterialAlias = {
  'material_chest': 'chest',
  'material_shoulders': 'front_deltoid',
  'material_upperarms': 'biceps',
  'material_abs': 'rectus_abdominis',
  'material_obliques': 'obliques',
  'material_quads': 'quadriceps',
  'material_glutes': 'glutes',
  'material_calves': 'calves',
  'material_lats': 'latissimus',
  'material_lowerback': 'erector_spinae',
  'material_neck': 'trapezius',
};

const List<MuscleHeatmapEntry> _mockEntries = [
  MuscleHeatmapEntry(
    muscleCode: 'chest',
    status: HeatmapStatus.red,
    fatigueScore: 2.9,
    displayScore: 92,
  ),
  MuscleHeatmapEntry(
    muscleCode: 'quadriceps',
    status: HeatmapStatus.yellow,
    fatigueScore: 2.1,
    displayScore: 74,
  ),
  MuscleHeatmapEntry(
    muscleCode: 'latissimus',
    status: HeatmapStatus.green,
    fatigueScore: 1.4,
    displayScore: 46,
  ),
  MuscleHeatmapEntry(
    muscleCode: 'glutes',
    status: HeatmapStatus.yellow,
    fatigueScore: 1.9,
    displayScore: 67,
  ),
];

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
  --poster-color: transparent;
  filter: contrast(1.08) saturate(1.05);
  touch-action: none;
}
''';
