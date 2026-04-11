import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../theme/app_theme.dart';

class InteractiveMuscle3DController extends ChangeNotifier {
  String? _runtimePayloadJson;
  String? _cameraOrbit;
  void Function(String orbit)? _cameraOrbitDelegate;

  String? get runtimePayloadJson => _runtimePayloadJson;
  String? get cameraOrbit => _cameraOrbit;

  void bindCameraOrbit(void Function(String orbit) delegate) {
    _cameraOrbitDelegate = delegate;
    final orbit = _cameraOrbit;
    if (orbit != null && orbit.isNotEmpty) {
      delegate(orbit);
    }
  }

  void unbindCameraOrbit(void Function(String orbit) delegate) {
    if (identical(_cameraOrbitDelegate, delegate)) {
      _cameraOrbitDelegate = null;
    }
  }

  void setRuntimePayloadJson(String payloadJson) {
    if (_runtimePayloadJson == payloadJson) {
      return;
    }
    _runtimePayloadJson = payloadJson;
    notifyListeners();
  }

  void setCameraOrbit(String orbit) {
    _cameraOrbit = orbit;
    _cameraOrbitDelegate?.call(orbit);
    notifyListeners();
  }
}

class InteractiveMuscle3DViewer extends StatefulWidget {
  const InteractiveMuscle3DViewer({
    super.key,
    required this.entries,
    this.borderRadius = 24,
    this.exposeBackgroundKey = false,
    this.interactive = true,
    this.autoRotate = false,
    this.showHotspots = false,
    this.highlightedMuscleCode,
    this.recommendedMuscleCode,
    this.autoFocusTargetMuscleCode,
    this.enableAutoFocusIntro = false,
    this.controller,
    this.onMuscleTap,
  });

  final List<MuscleHeatmapEntry> entries;
  final double borderRadius;
  final bool exposeBackgroundKey;
  final bool interactive;
  final bool autoRotate;
  final bool showHotspots;
  final String? highlightedMuscleCode;
  final String? recommendedMuscleCode;
  final String? autoFocusTargetMuscleCode;
  final bool enableAutoFocusIntro;
  final InteractiveMuscle3DController? controller;
  final ValueChanged<String>? onMuscleTap;

  @override
  State<InteractiveMuscle3DViewer> createState() =>
      _InteractiveMuscle3DViewerState();
}

class _InteractiveMuscle3DViewerState extends State<InteractiveMuscle3DViewer> {
  // Full-body high-resolution open-source anatomy model.
  static const String _myologyModelSrc =
      'https://raw.githubusercontent.com/shaikhmohammadtalha/android-anatomy-insight/main/app/src/main/assets/models/Myology.glb';
  static const String _fallbackBodyModelSrc =
      'https://raw.githubusercontent.com/hpfrei/body-anatomy-3d-viewer/main/public/body.glb';
  static const String _viewerId = 'musclecare-anatomy-viewer';
  static const String _defaultOrbit = '0deg 88deg 128%';

  WebViewController? _webViewController;
  Timer? _runtimeSyncTimer;
  Timer? _autoFocusResetTimer;
  bool _modelReady = false;
  int _runtimeAttempt = 0;
  int _modelSourceIndex = 0;
  int _reloadNonce = 0;
  String? _lastAppliedPayloadJson;
  String _cameraOrbit = _defaultOrbit;

  List<String> get _modelSourceCandidates => const [
        _myologyModelSrc,
        _fallbackBodyModelSrc,
      ];

  String get _activeModelSrc => _modelSourceCandidates[_modelSourceIndex];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleExternalControllerChanged);
    widget.controller?.bindCameraOrbit(_setCameraOrbitFromController);
    _applyInitialAutoFocus();
  }

  @override
  void didUpdateWidget(covariant InteractiveMuscle3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleExternalControllerChanged);
      oldWidget.controller?.unbindCameraOrbit(_setCameraOrbitFromController);
      widget.controller?.addListener(_handleExternalControllerChanged);
      widget.controller?.bindCameraOrbit(_setCameraOrbitFromController);
    }

    final previousPayload = _buildRuntimePayloadJson(fromWidget: oldWidget);
    final nextPayload = _buildRuntimePayloadJson();
    if (previousPayload != nextPayload) {
      _queueRuntimeSync(force: true);
    }

    final oldTarget =
        _canonicalizeMuscleCode(oldWidget.autoFocusTargetMuscleCode);
    final nextTarget =
        _canonicalizeMuscleCode(widget.autoFocusTargetMuscleCode);
    if (oldTarget != nextTarget ||
        oldWidget.enableAutoFocusIntro != widget.enableAutoFocusIntro) {
      _applyInitialAutoFocus();
    }
  }

  @override
  void dispose() {
    _runtimeSyncTimer?.cancel();
    _autoFocusResetTimer?.cancel();
    widget.controller?.removeListener(_handleExternalControllerChanged);
    widget.controller?.unbindCameraOrbit(_setCameraOrbitFromController);
    super.dispose();
  }

  void _handleExternalControllerChanged() {
    final payloadJson = widget.controller?.runtimePayloadJson;
    if (payloadJson == null || payloadJson.isEmpty) {
      return;
    }
    _queueRuntimeSync(forcedPayloadJson: payloadJson, force: true);
  }

  void _setCameraOrbitFromController(String orbit) {
    if (!mounted || orbit.trim().isEmpty) {
      return;
    }
    setState(() {
      _cameraOrbit = orbit;
    });
  }

  void _applyInitialAutoFocus() {
    _autoFocusResetTimer?.cancel();
    final targetCode =
        _canonicalizeMuscleCode(widget.autoFocusTargetMuscleCode);
    if (!widget.enableAutoFocusIntro ||
        targetCode == null ||
        targetCode.isEmpty) {
      return;
    }
    final expanded = _expandMuscleCode(targetCode);
    final preferred = expanded.isEmpty ? targetCode : expanded.first;
    _cameraOrbit = _orbitForMuscle(preferred);

    _autoFocusResetTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || !widget.interactive) {
        return;
      }
      setState(() {
        _cameraOrbit = _defaultOrbit;
      });
    });
  }

  void _queueRuntimeSync({String? forcedPayloadJson, bool force = false}) {
    _runtimeSyncTimer?.cancel();
    _runtimeSyncTimer = Timer(const Duration(milliseconds: 72), () async {
      if (!mounted || _webViewController == null || !_modelReady) {
        return;
      }
      final payloadJson = forcedPayloadJson ?? _buildRuntimePayloadJson();
      if (!force && payloadJson == _lastAppliedPayloadJson) {
        return;
      }
      _lastAppliedPayloadJson = payloadJson;
      widget.controller?.setRuntimePayloadJson(payloadJson);
      final escapedPayload = jsonEncode(payloadJson);
      try {
        await _webViewController!.runJavaScript(
          'window.applyMusclecareRuntime && '
          'window.applyMusclecareRuntime(JSON.parse($escapedPayload));',
        );
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _modelReady = false;
        });
      }
    });
  }

  void _retryModelLoad({bool advanceSource = false, bool resetAttempt = true}) {
    _runtimeSyncTimer?.cancel();
    _autoFocusResetTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _modelReady = false;
      if (resetAttempt) {
        _runtimeAttempt = 0;
      }
      _lastAppliedPayloadJson = null;
      if (advanceSource &&
          _modelSourceIndex < _modelSourceCandidates.length - 1) {
        _modelSourceIndex += 1;
      }
      _reloadNonce += 1;
    });
    _applyInitialAutoFocus();
  }

  String _buildRuntimePayloadJson({InteractiveMuscle3DViewer? fromWidget}) {
    final source = fromWidget ?? widget;
    final states = _computeMuscleStates(source);
    return jsonEncode({
      'highlighted': _resolvePreferredMuscleCode(source.highlightedMuscleCode),
      'recommended': _resolvePreferredMuscleCode(source.recommendedMuscleCode),
      'muscles': states.map((key, value) => MapEntry(key, value.toJson())),
    });
  }

  String? _resolvePreferredMuscleCode(String? rawCode) {
    final canonical = _canonicalizeMuscleCode(rawCode);
    if (canonical == null || canonical.isEmpty) {
      return null;
    }
    final expanded = _expandMuscleCode(canonical);
    if (expanded.isEmpty) {
      return canonical;
    }
    return expanded.first;
  }

  Map<String, _MuscleState> _computeMuscleStates(
    InteractiveMuscle3DViewer source,
  ) {
    final states = <String, _MuscleState>{};

    for (final muscleCode in _muscleMeshNodeMap.keys) {
      states[muscleCode] = _MuscleState.unknown();
    }

    for (final entry in source.entries) {
      final canonical = _canonicalizeMuscleCode(entry.muscleCode);
      if (canonical == null || canonical.isEmpty) {
        continue;
      }
      final nextState = _MuscleState.fromEntry(entry);
      for (final detailedCode in _expandMuscleCode(canonical)) {
        final existing = states[detailedCode];
        states[detailedCode] =
            existing == null ? nextState : existing.merge(nextState);
      }
    }

    final highlighted = _canonicalizeMuscleCode(source.highlightedMuscleCode);
    if (highlighted != null && highlighted.isNotEmpty) {
      for (final detailedCode in _expandMuscleCode(highlighted)) {
        states[detailedCode] = (states[detailedCode] ?? _MuscleState.unknown())
            .copyWith(focused: true);
      }
    }

    final recommended = _canonicalizeMuscleCode(source.recommendedMuscleCode);
    if (recommended != null && recommended.isNotEmpty) {
      for (final detailedCode in _expandMuscleCode(recommended)) {
        states[detailedCode] = (states[detailedCode] ?? _MuscleState.unknown())
            .copyWith(recommended: true);
      }
    }

    return states;
  }

  List<String> _expandMuscleCode(String canonicalCode) {
    final resolved = _muscleAliases[canonicalCode] ?? canonicalCode;
    final mapped = _entryToDetailedMuscles[resolved];
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
    if (_muscleMeshNodeMap.containsKey(resolved)) {
      return <String>[resolved];
    }
    return const <String>[];
  }

  String _resolveTapCode(String detailCode) {
    final canonical = _canonicalizeMuscleCode(detailCode);
    if (canonical == null || canonical.isEmpty) {
      return detailCode;
    }
    return _tapOutputCodeByDetailed[canonical] ?? canonical;
  }

  void _handleModelReadyMessage(String message) {
    if (!mounted) {
      return;
    }
    if (message == 'ready') {
      setState(() {
        _modelReady = true;
        _runtimeAttempt = 0;
      });
      _queueRuntimeSync(force: true);
      return;
    }
    if (message.startsWith('retry:')) {
      final retryCount = int.tryParse(message.split(':').last) ?? 0;
      setState(() {
        _runtimeAttempt = retryCount;
      });
      return;
    }
    if (message.startsWith('error:')) {
      if (_modelSourceIndex < _modelSourceCandidates.length - 1) {
        _retryModelLoad(advanceSource: true);
        return;
      }
      setState(() {
        _runtimeAttempt = (_runtimeAttempt + 1).clamp(1, 999);
        // Keep the viewer usable even if scene-graph API material pass fails.
        _modelReady = _runtimeAttempt >= 2;
      });
      if (!_modelReady) {
        _retryModelLoad(resetAttempt: false);
      }
    }
  }

  void _handleTapMessage(String message) {
    final resolved = _resolveTapCode(message);
    if (resolved.trim().isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    widget.onMuscleTap?.call(resolved);
  }

  @override
  Widget build(BuildContext context) {
    final primaryState = _resolvePrimaryState();
    final backgroundGradient = _buildDynamicGradient(primaryState);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            key: widget.exposeBackgroundKey
                ? const Key('viewer_dynamic_background')
                : null,
            decoration: BoxDecoration(gradient: backgroundGradient),
          ),
          _buildLiveViewer(context),
          _buildEdgeGlow(),
          _buildStatusOverlay(),
        ],
      ),
    );
  }

  Widget _buildLiveViewer(BuildContext context) {
    final modelViewer = ModelViewer(
      key: ValueKey(
        'interactive_muscle_3d_viewer_${_modelSourceIndex}_$_reloadNonce',
      ),
      src: _activeModelSrc,
      id: _viewerId,
      backgroundColor: Colors.transparent,
      cameraControls: widget.interactive,
      disablePan: true,
      disableZoom: true,
      disableTap: !widget.interactive,
      touchAction: TouchAction.none,
      autoRotate: widget.interactive ? widget.autoRotate : false,
      autoRotateDelay: 1400,
      rotationPerSecond: '20deg',
      cameraOrbit: _cameraOrbit,
      cameraTarget: '0m 0.84m 0m',
      fieldOfView: '28deg',
      minCameraOrbit: 'auto 70deg 112%',
      maxCameraOrbit: 'auto 110deg 152%',
      interpolationDecay: 180,
      environmentImage: 'neutral',
      exposure: 1.5,
      shadowSoftness: 1.0,
      loading: Loading.eager,
      reveal: Reveal.auto,
      interactionPrompt: InteractionPrompt.none,
      debugLogging: false,
      relatedCss: _buildViewerCss(),
      relatedJs: _buildViewerJs(),
      javascriptChannels: {
        JavascriptChannel(
          'ModelReady',
          onMessageReceived: (message) =>
              _handleModelReadyMessage(message.message),
        ),
        JavascriptChannel(
          'TapChannel',
          onMessageReceived: (message) => _handleTapMessage(message.message),
        ),
      },
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
    );

    final viewerWidget = widget.interactive
        ? RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
            },
            child: modelViewer,
          )
        : modelViewer;

    return Stack(
      fit: StackFit.expand,
      children: [
        viewerWidget,
        if (!_modelReady) _buildLoadingOverlay(context),
      ],
    );
  }

  Widget _buildLoadingOverlay(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.20),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.surface1.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'heatmap.interactive3d.loading'.tr(),
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMediumStyle.copyWith(
                        color: AppTheme.textHigh,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _runtimeAttempt > 0
                          ? 'heatmap.interactive3d.retrying'
                              .tr(namedArgs: {'count': '$_runtimeAttempt'})
                          : 'heatmap.interactive3d.optimizing'.tr(),
                      textAlign: TextAlign.center,
                      style: AppTheme.labelSmallStyle.copyWith(
                        color: AppTheme.textLow,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _modelReady = false;
                          _runtimeAttempt = 0;
                          _lastAppliedPayloadJson = null;
                        });
                        _queueRuntimeSync(force: true);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('heatmap.interactive3d.retry'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOverlay() {
    final primaryState = _resolvePrimaryState();
    if (primaryState == null) {
      return const SizedBox.shrink();
    }
    final accent = _statusAccentColor(primaryState.status);
    return Positioned(
      left: 14,
      bottom: 14,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.36),
            borderRadius: AppTheme.buttonRadius,
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: accent),
                ),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(primaryState.status),
                  style: AppTheme.labelSmallStyle.copyWith(
                    color: AppTheme.textHigh,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeGlow() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.78),
            radius: 1.1,
            colors: [
              Colors.white.withValues(alpha: 0.07),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _buildDynamicGradient(_MuscleState? primaryState) {
    final accent =
        _statusAccentColor(primaryState?.status ?? HeatmapStatus.green);
    final intensity = primaryState?.intensity ?? 0.28;
    final focusedBoost = primaryState?.focused == true ? 0.22 : 0.0;
    final recommendedBoost = primaryState?.recommended == true ? 0.14 : 0.0;
    final alpha = (0.18 + (intensity * 0.20) + focusedBoost + recommendedBoost)
        .clamp(0.18, 0.46);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF070B11),
        Color.lerp(
          AppTheme.surface2,
          accent,
          0.20 + (intensity * 0.20) + focusedBoost,
        )!
            .withValues(alpha: alpha.toDouble()),
        const Color(0xFF060A0F),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
  }

  _MuscleState? _resolvePrimaryState() {
    final states = _computeMuscleStates(widget);
    final highlighted =
        _resolvePreferredMuscleCode(widget.highlightedMuscleCode);
    if (highlighted != null && states[highlighted] != null) {
      return states[highlighted];
    }
    final recommended =
        _resolvePreferredMuscleCode(widget.recommendedMuscleCode);
    if (recommended != null && states[recommended] != null) {
      return states[recommended];
    }
    final sorted = states.values
        .where(
          (state) =>
              state.status != HeatmapStatus.unknown ||
              state.focused ||
              state.recommended,
        )
        .toList()
      ..sort((a, b) => b.visualPriority.compareTo(a.visualPriority));
    if (sorted.isEmpty) {
      return null;
    }
    return sorted.first;
  }

  Color _statusAccentColor(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return const Color(0xFFFF4D6D);
      case HeatmapStatus.yellow:
        return const Color(0xFFFFC857);
      case HeatmapStatus.green:
        return const Color(0xFF41F28D);
      case HeatmapStatus.unknown:
        return const Color(0xFF7DA0B8);
    }
  }

  String _statusLabel(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return 'RED';
      case HeatmapStatus.yellow:
        return 'YELLOW';
      case HeatmapStatus.green:
        return 'GREEN';
      case HeatmapStatus.unknown:
        return 'READY';
    }
  }

  String _orbitForMuscle(String muscleCode) {
    final direct = _orbitByMuscle[muscleCode];
    if (direct != null) {
      return direct;
    }
    final parent = _tapOutputCodeByDetailed[muscleCode];
    if (parent != null && _orbitByMuscle[parent] != null) {
      return _orbitByMuscle[parent]!;
    }
    return _defaultOrbit;
  }

  String _buildViewerCss() {
    return '''
      :host {
        --progress-mask: transparent;
      }

      model-viewer {
        width: 100%;
        height: 100%;
        background:
          radial-gradient(circle at 50% 7%, rgba(109, 205, 255, 0.08), transparent 36%),
          radial-gradient(circle at 50% 100%, rgba(17, 24, 34, 0.95), rgba(7, 9, 14, 0.98));
        filter: contrast(1.22) saturate(1.12) brightness(1.05);
        cursor: grab;
      }

      model-viewer:active {
        cursor: grabbing;
      }
    ''';
  }

  String _buildViewerJs() {
    final muscleNodeMapJson = jsonEncode(_muscleMeshNodeMap);
    final initialPayloadJson = _buildRuntimePayloadJson();
    return '''
      (() => {
        const viewer = document.querySelector('#$_viewerId');
        if (!viewer) {
          return;
        }

        const muscleNodeMap = $muscleNodeMapJson;
        const runtimeState = {
          payload: $initialPayloadJson,
          materialToMuscle: new Map(),
          nodeToMuscle: new Map(),
          dominantMuscle: null,
        };

        const normalize = (value) => {
          let text = String(value || '').toLowerCase();
          text = text.replace(/generated_mesh_from_x3d[^a-z0-9_]*/g, '');
          text = text.replace(/grp\\d+[^a-z0-9_]*/g, '');
          text = text.replace(/plane\\.\\d+[^a-z0-9_]*/g, '');
          text = text.replace(/cube\\.\\d+[^a-z0-9_]*/g, '');
          text = text.replace(/'/g, '');
          text = text.replace(/[^a-z0-9]+/g, '_');
          text = text.replace(/_+/g, '_').replace(/^_+|_+\$/g, '');
          if (!text) {
            return '';
          }
          const tokens = text
            .split('_')
            .filter(Boolean)
            .filter((token, index, arr) => {
              if (index !== arr.length - 1) {
                return true;
              }
              return !/^\\d+\$/.test(token);
            })
            .filter((token) => !['l', 'r', 'left', 'right'].includes(token));
          return tokens.join('_');
        };

        const parseScalar = (value) => {
          const scalar = Number.parseFloat(String(value ?? '').trim());
          return Number.isFinite(scalar) ? scalar : 0;
        };

        const parseVector = (value) => {
          if (!value) {
            return [0, 0, 0];
          }
          if (Array.isArray(value)) {
            return value.map((entry) => parseScalar(entry));
          }
          return String(value)
            .trim()
            .split(/\\s+/)
            .filter(Boolean)
            .slice(0, 3)
            .map((entry) => parseScalar(entry));
        };

        const normalizedNodeMap = Object.entries(muscleNodeMap).map(
          ([muscleCode, signatures]) => [
            muscleCode,
            (signatures || []).map((entry) => normalize(entry)).filter(Boolean),
          ],
        );

        const resolveMuscleCode = (signature) => {
          const normalized = normalize(signature);
          if (!normalized) {
            return null;
          }
          for (const [muscleCode, signatures] of normalizedNodeMap) {
            for (const candidate of signatures) {
              if (
                normalized === candidate ||
                normalized.includes(candidate) ||
                candidate.includes(normalized)
              ) {
                return muscleCode;
              }
            }
          }
          return null;
        };

        const enforceViewerConstraints = () => {
          viewer.setAttribute('disable-zoom', '');
          viewer.setAttribute('disable-pan', '');
          viewer.setAttribute('shadow-intensity', '3.0');
          viewer.setAttribute('shadow-softness', '1.0');
          viewer.setAttribute('exposure', '1.5');
          viewer.setAttribute('environment-image', 'neutral');
        };

        const colors = {
          neutral: [0.15, 0.18, 0.23],
          green: [0.20, 0.98, 0.56],
          yellow: [1.00, 0.78, 0.28],
          red: [1.00, 0.32, 0.46],
          focus: [0.55, 1.00, 0.76],
          recommend: [0.24, 0.92, 1.00],
        };

        const resolveMaterialState = (muscleCode) => {
          const payload = runtimeState.payload || {};
          const muscles = payload.muscles || {};
          const state = muscles[muscleCode] || {};
          return {
            status: state.status || 'unknown',
            intensity: Number(state.intensity || 0.24),
            focused: Boolean(state.focused),
            recommended: Boolean(state.recommended),
          };
        };

        const resolveDominantMuscle = () => {
          const payload = runtimeState.payload || {};
          const muscles = payload.muscles || {};
          let bestCode = null;
          let bestScore = -1;
          for (const [muscleCode, state] of Object.entries(muscles)) {
            const statusWeight =
              state.status === 'red'
                ? 4
                : state.status === 'yellow'
                  ? 3
                  : state.status === 'green'
                    ? 2
                    : 1;
            const score =
              statusWeight +
              Number(state.intensity || 0) +
              (state.focused ? 1.2 : 0) +
              (state.recommended ? 0.8 : 0);
            if (score > bestScore) {
              bestScore = score;
              bestCode = muscleCode;
            }
          }
          runtimeState.dominantMuscle = bestCode;
          return bestCode;
        };

        const applyAppearance = (material, muscleCode) => {
          const state = resolveMaterialState(muscleCode);
          let base = colors.neutral;
          if (state.status === 'green') {
            base = colors.green;
          } else if (state.status === 'yellow') {
            base = colors.yellow;
          } else if (state.status === 'red') {
            base = colors.red;
          }

          let mix = 0.20 + Math.min(Math.max(state.intensity, 0.0), 1.0) * 0.48;
          if (state.focused) {
            base = colors.focus;
            mix += 0.22;
          } else if (state.recommended) {
            base = colors.recommend;
            mix += 0.14;
          }
          mix = Math.min(mix, 0.90);

          const neutral = colors.neutral;
          const finalColor = [
            neutral[0] + (base[0] - neutral[0]) * mix,
            neutral[1] + (base[1] - neutral[1]) * mix,
            neutral[2] + (base[2] - neutral[2]) * mix,
            1.0,
          ];
          const emissive = state.focused
            ? [base[0] * 0.44, base[1] * 0.44, base[2] * 0.44]
            : state.recommended
              ? [base[0] * 0.22, base[1] * 0.22, base[2] * 0.22]
              : [0.0, 0.0, 0.0];

          material.pbrMetallicRoughness.setBaseColorFactor(finalColor);
          // Mandatory premium PBR injection.
          material.pbrMetallicRoughness.setRoughnessFactor(0.3);
          material.pbrMetallicRoughness.setMetallicFactor(0.6);
          if (material.setEmissiveFactor) {
            material.setEmissiveFactor(emissive);
          }
        };

        const applyNeutralAppearance = (material) => {
          material.pbrMetallicRoughness.setBaseColorFactor([
            colors.neutral[0],
            colors.neutral[1],
            colors.neutral[2],
            1.0,
          ]);
          material.pbrMetallicRoughness.setRoughnessFactor(0.74);
          material.pbrMetallicRoughness.setMetallicFactor(0.12);
          if (material.setEmissiveFactor) {
            material.setEmissiveFactor([0.0, 0.0, 0.0]);
          }
        };

        const rebuildNodeLookup = () => {
          runtimeState.nodeToMuscle.clear();
          const source =
            viewer.originalGltfJson ||
            (viewer.model && viewer.model.originalGltfJson) ||
            null;
          if (!source || !Array.isArray(source.nodes)) {
            return 0;
          }
          let indexed = 0;
          for (const node of source.nodes) {
            const nodeName = node && node.name ? node.name : '';
            const muscleCode = resolveMuscleCode(nodeName);
            if (muscleCode) {
              runtimeState.nodeToMuscle.set(normalize(nodeName), muscleCode);
              indexed += 1;
            }
          }
          return indexed;
        };

        const rebuildMaterialLookup = () => {
          runtimeState.materialToMuscle.clear();
          if (!viewer.model || !Array.isArray(viewer.model.materials)) {
            return 0;
          }
          const dominantMuscle = resolveDominantMuscle();
          let indexed = 0;
          for (const material of viewer.model.materials) {
            const materialName = material && material.name ? material.name : '';
            const normalizedName = normalize(materialName);
            let muscleCode = resolveMuscleCode(materialName);
            if (
              !muscleCode &&
              dominantMuscle &&
              (normalizedName.includes('muscle') || normalizedName.includes('tendon'))
            ) {
              muscleCode = dominantMuscle;
            }
            if (muscleCode) {
              runtimeState.materialToMuscle.set(normalizedName, muscleCode);
              indexed += 1;
            }
          }
          return indexed;
        };

        const applyAllMaterials = () => {
          if (!viewer.model || !Array.isArray(viewer.model.materials)) {
            return false;
          }
          enforceViewerConstraints();
          rebuildNodeLookup();
          if (runtimeState.materialToMuscle.size === 0) {
            rebuildMaterialLookup();
          }

          const dominantMuscle = runtimeState.dominantMuscle || resolveDominantMuscle();

          for (const material of viewer.model.materials) {
            const materialName = material && material.name ? material.name : '';
            const normalizedName = normalize(materialName);
            const resolved =
              runtimeState.materialToMuscle.get(normalizedName) ||
              (dominantMuscle &&
              (normalizedName.includes('muscle') || normalizedName.includes('tendon'))
                ? dominantMuscle
                : null);
            if (resolved) {
              applyAppearance(material, resolved);
            } else {
              applyNeutralAppearance(material);
            }
          }
          return true;
        };

        const resolveTapMuscle = (event) => {
          if (!event || !viewer) {
            return null;
          }
          const rect = viewer.getBoundingClientRect();
          const x = event.clientX - rect.left;
          const y = event.clientY - rect.top;

          try {
            const model = viewer.model || null;
            const node =
              model && model.nodeFromPoint
                ? model.nodeFromPoint(x, y)
                : viewer.nodeFromPoint
                  ? viewer.nodeFromPoint(x, y)
                  : null;
            const fromNode = resolveMuscleCode(node && node.name ? node.name : '');
            if (fromNode) {
              return fromNode;
            }
          } catch (_) {}

          try {
            const material = viewer.materialFromPoint ? viewer.materialFromPoint(x, y) : null;
            const fromMaterial = resolveMuscleCode(
              material && material.name ? material.name : '',
            );
            if (fromMaterial) {
              return fromMaterial;
            }
          } catch (_) {}

          try {
            const surface = viewer.surfaceFromPoint ? viewer.surfaceFromPoint(x, y) : null;
            const fromSurface = resolveMuscleCode(surface ? String(surface) : '');
            if (fromSurface) {
              return fromSurface;
            }
          } catch (_) {}

          try {
            const hit = viewer.positionAndNormalFromPoint
              ? viewer.positionAndNormalFromPoint(x, y)
              : null;
            const fromPoint = resolveMuscleCode(JSON.stringify({
              position: parseVector(hit && hit.position),
              normal: parseVector(hit && hit.normal),
            }));
            if (fromPoint) {
              return fromPoint;
            }
          } catch (_) {}

          return runtimeState.dominantMuscle;
        };

        let readyPosted = false;
        const notifyReadyOnce = () => {
          if (readyPosted) {
            return;
          }
          readyPosted = true;
          ModelReady.postMessage('ready');
        };

        const scheduleReadyProbe = (attempt = 0) => {
          try {
            enforceViewerConstraints();
            const applied = applyAllMaterials();
            if (applied) {
              return;
            }
            const nextAttempt = attempt + 1;
            ModelReady.postMessage('retry:' + nextAttempt);
            if (nextAttempt < 320) {
              window.setTimeout(() => scheduleReadyProbe(nextAttempt), 260);
            } else {
              ModelReady.postMessage('error:scene_graph_unavailable');
            }
          } catch (_) {
            const nextAttempt = attempt + 1;
            ModelReady.postMessage('retry:' + nextAttempt);
            if (nextAttempt < 320) {
              window.setTimeout(() => scheduleReadyProbe(nextAttempt), 320);
            } else {
              ModelReady.postMessage('error:scene_graph_runtime_exception');
            }
          }
        };

        window.applyMusclecareRuntime = (payload) => {
          runtimeState.payload = payload || {};
          runtimeState.materialToMuscle.clear();
          try {
            applyAllMaterials();
          } catch (_) {}
        };

        viewer.addEventListener('load', () => {
          notifyReadyOnce();
          scheduleReadyProbe(0);
        });

        viewer.addEventListener('scene-graph-ready', () => {
          notifyReadyOnce();
          scheduleReadyProbe(0);
        });

        viewer.addEventListener('error', () => {
          ModelReady.postMessage('error:model_load_failed');
        });

        viewer.addEventListener('click', (event) => {
          const muscleCode = resolveTapMuscle(event);
          if (muscleCode) {
            TapChannel.postMessage(muscleCode);
          }
        });

        enforceViewerConstraints();
        window.setTimeout(() => notifyReadyOnce(), 4000);
        scheduleReadyProbe(0);
      })();
    ''';
  }
}

class _MuscleState {
  const _MuscleState({
    required this.status,
    required this.intensity,
    this.focused = false,
    this.recommended = false,
  });

  factory _MuscleState.fromEntry(MuscleHeatmapEntry entry) {
    final normalizedIntensity = switch (entry.status) {
      HeatmapStatus.red => math.max(0.76, entry.fatigueScore / 2.0),
      HeatmapStatus.yellow => math.max(0.52, entry.fatigueScore / 2.0),
      HeatmapStatus.green => math.max(0.28, entry.fatigueScore / 2.0),
      HeatmapStatus.unknown => 0.24,
    };
    return _MuscleState(
      status: entry.status,
      intensity: normalizedIntensity.clamp(0.16, 1.0),
    );
  }

  factory _MuscleState.unknown() {
    return const _MuscleState(status: HeatmapStatus.unknown, intensity: 0.24);
  }

  final HeatmapStatus status;
  final double intensity;
  final bool focused;
  final bool recommended;

  double get visualPriority {
    final statusWeight = switch (status) {
      HeatmapStatus.red => 4.0,
      HeatmapStatus.yellow => 3.0,
      HeatmapStatus.green => 2.0,
      HeatmapStatus.unknown => 1.0,
    };
    return statusWeight +
        intensity +
        (focused ? 1.2 : 0.0) +
        (recommended ? 0.8 : 0.0);
  }

  _MuscleState merge(_MuscleState other) {
    final resolvedStatus = _statusOrder(status) >= _statusOrder(other.status)
        ? status
        : other.status;
    return _MuscleState(
      status: resolvedStatus,
      intensity: math.max(intensity, other.intensity),
      focused: focused || other.focused,
      recommended: recommended || other.recommended,
    );
  }

  _MuscleState copyWith({
    HeatmapStatus? status,
    double? intensity,
    bool? focused,
    bool? recommended,
  }) {
    return _MuscleState(
      status: status ?? this.status,
      intensity: intensity ?? this.intensity,
      focused: focused ?? this.focused,
      recommended: recommended ?? this.recommended,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.rawValue,
      'intensity': intensity,
      'focused': focused,
      'recommended': recommended,
    };
  }

  static int _statusOrder(HeatmapStatus value) {
    switch (value) {
      case HeatmapStatus.red:
        return 3;
      case HeatmapStatus.yellow:
        return 2;
      case HeatmapStatus.green:
        return 1;
      case HeatmapStatus.unknown:
        return 0;
    }
  }
}

String? _canonicalizeMuscleCode(String? raw) {
  if (raw == null) {
    return null;
  }
  var normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  normalized = normalized.replaceAll(RegExp(r'generated_mesh_from_x3d.*$'), '');
  normalized = normalized.replaceAll(RegExp(r'grp\d+.*$'), '');
  normalized = normalized.replaceAll(RegExp(r'plane\.\d+.*$'), '');
  normalized = normalized.replaceAll(RegExp(r'cube\.\d+.*$'), '');
  normalized = normalized.replaceAll('\'', '');
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.isEmpty) {
    return null;
  }
  final tokens = normalized
      .split('_')
      .where((token) => token.isNotEmpty)
      .where((token) => !_sideTokens.contains(token))
      .toList();
  if (tokens.isNotEmpty && RegExp(r'^\d+$').hasMatch(tokens.last)) {
    tokens.removeLast();
  }
  final compact = tokens.join('_');
  if (compact.isEmpty) {
    return null;
  }
  return _muscleAliases[compact] ?? compact;
}

const Set<String> _sideTokens = {
  'left',
  'right',
  'l',
  'r',
  'lt',
  'rt',
  'lhs',
  'rhs',
};

const Map<String, String> _muscleAliases = {
  'pecs': 'chest',
  'pectoralis_major': 'chest',
  'pectoral': 'chest',
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
  'core': 'rectus_abdominis',
  'oblique': 'obliques',
  'front_delts': 'front_deltoid',
  'anterior_deltoid': 'front_deltoid',
  'deltoid_anterior': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'side_deltoid': 'lateral_deltoid',
  'deltoid_lateral': 'lateral_deltoid',
  'rear_delts': 'rear_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'deltoid_posterior': 'rear_deltoid',
  'lats': 'latissimus',
  'latissimus_dorsi': 'latissimus',
  'latissimus_upper': 'latissimus',
  'latissimus_lower': 'latissimus',
  'traps': 'trapezius',
  'upper_trap': 'trapezius',
  'middle_trap': 'trapezius',
  'lower_trap': 'trapezius',
  'rhomboid': 'rhomboids',
  'biceps_brachii': 'biceps',
  'triceps_brachii': 'triceps',
  'forearm': 'forearm_flexor',
  'forearms': 'forearm_flexor',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'glutes': 'gluteus_maximus',
  'glute_maximus': 'gluteus_maximus',
  'glute_medius': 'gluteus_medius',
  'glute_minimus': 'gluteus_minimus',
  'quads': 'quadriceps',
  'hamstring': 'hamstrings',
  'adductor': 'adductors',
  'abductor': 'abductors',
  'calf': 'calves',
  'gastrocnemius_medial': 'gastrocnemius',
  'gastrocnemius_lateral': 'gastrocnemius',
  'shin': 'tibialis_anterior',
  'erectors': 'erector_spinae',
  'spinal_erectors': 'erector_spinae',
  'scapular_part_of_deltoid_uscle': 'deltoid_posterior',
  'scapular_part_of_deltoid_muscle': 'deltoid_posterior',
  'deep_head_of_prontaor_teres_muscle': 'pronator_teres_deep',
  'internal_intercosatlis_muscles': 'internal_intercostals',
};

const Map<String, List<String>> _entryToDetailedMuscles = {
  'chest': [
    'pectoralis_major_clavicular',
    'pectoralis_major_sternocostal',
    'pectoralis_major_abdominal',
    'pectoralis_minor',
    'serratus_anterior',
  ],
  'front_deltoid': ['deltoid_anterior'],
  'lateral_deltoid': ['deltoid_lateral'],
  'rear_deltoid': ['deltoid_posterior'],
  'trapezius': [
    'trapezius_descending',
    'trapezius_transverse',
    'trapezius_ascending',
  ],
  'rhomboids': ['rhomboid_major', 'rhomboid_minor'],
  'latissimus': ['latissimus_dorsi'],
  'biceps': ['biceps_brachii_long_head', 'biceps_brachii_short_head'],
  'triceps': [
    'triceps_brachii_long_head',
    'triceps_brachii_lateral_head',
    'triceps_brachii_medial_head',
  ],
  'forearm_flexor': [
    'pronator_teres_superficial',
    'pronator_teres_deep',
    'flexor_carpi_radialis',
    'flexor_carpi_ulnaris',
    'palmaris_longus',
  ],
  'forearm_extensor': [
    'supinator',
    'extensor_carpi_radialis_longus',
    'extensor_carpi_radialis_brevis',
    'extensor_carpi_ulnaris',
    'extensor_digitorum',
    'extensor_digiti_minimi',
    'brachioradialis',
  ],
  'rectus_abdominis': ['rectus_abdominis'],
  'obliques': ['external_oblique', 'internal_oblique'],
  'transverse_abdominis': ['transversus_abdominis'],
  'erector_spinae': [
    'iliocostalis_lumborum',
    'iliocostalis_thoracis',
    'iliocostalis_cervicis',
    'longissimus_thoracis',
    'spinalis_thoracis',
    'multifidus',
  ],
  'lower_back': [
    'quadratus_lumborum',
    'multifidus',
    'iliocostalis_lumborum',
    'longissimus_thoracis',
  ],
  'gluteus_maximus': ['gluteus_maximus'],
  'gluteus_medius': ['gluteus_medius'],
  'gluteus_minimus': ['gluteus_minimus'],
  'abductors': ['gluteus_medius', 'gluteus_minimus', 'piriformis'],
  'adductors': [
    'adductor_longus',
    'adductor_brevis',
    'adductor_magnus',
    'adductor_minimus',
    'gracilis',
    'pectineus',
  ],
  'quadriceps': [
    'rectus_femoris',
    'vastus_lateralis',
    'vastus_medialis',
    'vastus_intermedius',
  ],
  'hamstrings': [
    'biceps_femoris_long_head',
    'biceps_femoris_short_head',
    'semitendinosus',
    'semimembranosus',
  ],
  'calves': [
    'gastrocnemius_medial_head',
    'gastrocnemius_lateral_head',
    'soleus',
    'plantaris',
  ],
  'gastrocnemius': ['gastrocnemius_medial_head', 'gastrocnemius_lateral_head'],
  'tibialis_anterior': ['tibialis_anterior'],
  'tibialis_posterior': ['tibialis_posterior'],
  'neck': ['sternocleidomastoid', 'splenius_capitis', 'splenius_cervicis'],
};

const Map<String, String> _tapOutputCodeByDetailed = {
  'pectoralis_major_clavicular': 'chest',
  'pectoralis_major_sternocostal': 'chest',
  'pectoralis_major_abdominal': 'chest',
  'pectoralis_minor': 'chest',
  'serratus_anterior': 'chest',
  'deltoid_anterior': 'front_deltoid',
  'deltoid_lateral': 'lateral_deltoid',
  'deltoid_posterior': 'rear_deltoid',
  'trapezius_descending': 'trapezius',
  'trapezius_transverse': 'trapezius',
  'trapezius_ascending': 'trapezius',
  'rhomboid_major': 'rhomboids',
  'rhomboid_minor': 'rhomboids',
  'latissimus_dorsi': 'latissimus',
  'biceps_brachii_long_head': 'biceps',
  'biceps_brachii_short_head': 'biceps',
  'triceps_brachii_long_head': 'triceps',
  'triceps_brachii_lateral_head': 'triceps',
  'triceps_brachii_medial_head': 'triceps',
  'pronator_teres_superficial': 'forearm_flexor',
  'pronator_teres_deep': 'forearm_flexor',
  'flexor_carpi_radialis': 'forearm_flexor',
  'flexor_carpi_ulnaris': 'forearm_flexor',
  'palmaris_longus': 'forearm_flexor',
  'extensor_carpi_radialis_longus': 'forearm_extensor',
  'extensor_carpi_radialis_brevis': 'forearm_extensor',
  'extensor_carpi_ulnaris': 'forearm_extensor',
  'extensor_digitorum': 'forearm_extensor',
  'extensor_digiti_minimi': 'forearm_extensor',
  'supinator': 'forearm_extensor',
  'brachioradialis': 'forearm_extensor',
  'rectus_abdominis': 'rectus_abdominis',
  'external_oblique': 'obliques',
  'internal_oblique': 'obliques',
  'transversus_abdominis': 'transverse_abdominis',
  'iliocostalis_lumborum': 'erector_spinae',
  'iliocostalis_thoracis': 'erector_spinae',
  'iliocostalis_cervicis': 'erector_spinae',
  'longissimus_thoracis': 'erector_spinae',
  'spinalis_thoracis': 'erector_spinae',
  'multifidus': 'erector_spinae',
  'quadratus_lumborum': 'lower_back',
  'gluteus_maximus': 'gluteus_maximus',
  'gluteus_medius': 'gluteus_medius',
  'gluteus_minimus': 'gluteus_minimus',
  'piriformis': 'abductors',
  'gemellus_superior': 'abductors',
  'gemellus_inferior': 'abductors',
  'quadratus_femoris': 'abductors',
  'adductor_longus': 'adductors',
  'adductor_brevis': 'adductors',
  'adductor_magnus': 'adductors',
  'adductor_minimus': 'adductors',
  'gracilis': 'adductors',
  'pectineus': 'adductors',
  'rectus_femoris': 'quadriceps',
  'vastus_lateralis': 'quadriceps',
  'vastus_medialis': 'quadriceps',
  'vastus_intermedius': 'quadriceps',
  'biceps_femoris_long_head': 'hamstrings',
  'biceps_femoris_short_head': 'hamstrings',
  'semitendinosus': 'hamstrings',
  'semimembranosus': 'hamstrings',
  'gastrocnemius_medial_head': 'gastrocnemius',
  'gastrocnemius_lateral_head': 'gastrocnemius',
  'soleus': 'calves',
  'plantaris': 'calves',
  'tibialis_anterior': 'tibialis_anterior',
  'tibialis_posterior': 'tibialis_posterior',
  'sternocleidomastoid': 'neck',
  'splenius_capitis': 'neck',
  'splenius_cervicis': 'neck',
};

const Map<String, String> _orbitByMuscle = {
  'chest': '0deg 84deg 118%',
  'rectus_abdominis': '0deg 92deg 124%',
  'obliques': '24deg 90deg 126%',
  'front_deltoid': '28deg 84deg 120%',
  'lateral_deltoid': '62deg 86deg 124%',
  'rear_deltoid': '212deg 86deg 124%',
  'biceps': '52deg 84deg 124%',
  'triceps': '232deg 84deg 126%',
  'forearm_flexor': '66deg 92deg 132%',
  'forearm_extensor': '248deg 92deg 132%',
  'latissimus': '206deg 84deg 126%',
  'trapezius': '182deg 74deg 122%',
  'rhomboids': '186deg 80deg 126%',
  'gluteus_maximus': '180deg 92deg 116%',
  'quadriceps': '0deg 96deg 132%',
  'hamstrings': '180deg 96deg 134%',
  'calves': '180deg 104deg 142%',
  'gastrocnemius': '180deg 104deg 140%',
  'tibialis_anterior': '0deg 102deg 140%',
  'neck': '0deg 76deg 116%',
  'latissimus_dorsi': '206deg 84deg 126%',
  'deltoid_anterior': '28deg 84deg 120%',
  'deltoid_lateral': '62deg 86deg 124%',
  'deltoid_posterior': '212deg 86deg 124%',
  'gluteus_medius': '188deg 90deg 120%',
  'gluteus_minimus': '188deg 90deg 120%',
  'rectus_femoris': '0deg 96deg 132%',
  'vastus_lateralis': '8deg 96deg 132%',
  'vastus_medialis': '-8deg 96deg 132%',
  'vastus_intermedius': '0deg 96deg 132%',
  'biceps_femoris_long_head': '184deg 98deg 134%',
  'biceps_femoris_short_head': '184deg 98deg 134%',
  'semitendinosus': '176deg 98deg 134%',
  'semimembranosus': '176deg 98deg 134%',
  'gastrocnemius_medial_head': '176deg 104deg 142%',
  'gastrocnemius_lateral_head': '186deg 104deg 142%',
};

const Map<String, List<String>> _muscleMeshNodeMap = {
  'pectoralis_major_clavicular': [
    'clavicular_head_of_pectoralis_major_muscle',
  ],
  'pectoralis_major_sternocostal': [
    'sternocostal_head_of_pectoralis_major_muscle',
  ],
  'pectoralis_major_abdominal': [
    'abdominal_part_of_pectoralis_major_muscle',
  ],
  'pectoralis_minor': [
    'pectoralis_minor_muscle',
  ],
  'serratus_anterior': [
    'serratus_anterior_muscle',
  ],
  'serratus_posterior_superior': [
    'serratus_posterior_superior_muscle',
  ],
  'serratus_posterior_inferior': [
    'serratus_posterior_inferior_muscle',
  ],
  'subclavius': [
    'subclavius_muscle',
  ],
  'deltoid_anterior': [
    'clavicular_part_of_deltoid_muscle',
  ],
  'deltoid_lateral': [
    'acromial_part_of_deltoid_muscle',
  ],
  'deltoid_posterior': [
    'scapular_part_of_deltoid_uscle',
    'scapular_part_of_deltoid_muscle',
  ],
  'trapezius_descending': [
    'descending_part_of_trapezius_muscle',
  ],
  'trapezius_transverse': [
    'transverse_part_of_trapezius_muscle',
  ],
  'trapezius_ascending': [
    'ascending_part_of_trapezius_muscle',
  ],
  'rhomboid_major': [
    'rhomboid_major_muscle',
  ],
  'rhomboid_minor': [
    'rhomboid_minor_muscle',
  ],
  'latissimus_dorsi': [
    'latissimus_dorsi_muscle',
  ],
  'teres_major': [
    'teres_major_muscle',
  ],
  'teres_minor': [
    'teres_minor_muscle',
  ],
  'supraspinatus': [
    'supraspinatus_muscle',
  ],
  'infraspinatus': [
    'infraspinatus_muscle',
  ],
  'subscapularis': [
    'subscapular_muscle',
  ],
  'levator_scapulae': [
    'levator_scapulae_muscle',
  ],
  'biceps_brachii_long_head': [
    'long_head_of_biceps_brachii_muscle',
    'long_head_of_biceps_brachii',
  ],
  'biceps_brachii_short_head': [
    'short_head_of_biceps_brachii',
  ],
  'brachialis': [
    'brachialis_muscle',
  ],
  'brachioradialis': [
    'brachioradialis_muscle',
  ],
  'coracobrachialis': [
    'coracobrachialis_muscle',
  ],
  'triceps_brachii_long_head': [
    'long_head_of_triceps_brachii_muscle',
    'triceps_long_head',
  ],
  'triceps_brachii_lateral_head': [
    'lateral_head_of_triceps_brachii_muscle',
    'triceps_lateral_head',
  ],
  'triceps_brachii_medial_head': [
    'medial_head_of_triceps_brachii_muscle',
    'medial_head_of_biceps_brachii_muscle',
  ],
  'anconeus': [
    'anconeus_muscle',
  ],
  'pronator_teres_superficial': [
    'superficial_head_of_pronator_teres_muscle',
  ],
  'pronator_teres_deep': [
    'deep_head_of_pronator_teres_muscle',
    'deep_head_of_prontaor_teres_muscle',
  ],
  'supinator': [
    'supinator_muscle',
  ],
  'flexor_carpi_radialis': [
    'flexor_carpi_radialis_muscle',
  ],
  'flexor_carpi_ulnaris': [
    'flexor_carpi_ulnaris_muscle',
  ],
  'palmaris_longus': [
    'palmaris_longus_muscle',
  ],
  'extensor_carpi_radialis_longus': [
    'extensor_carpi_radialis_longus_muscle',
  ],
  'extensor_carpi_radialis_brevis': [
    'extensor_carpi_radialis_brevis_muscle',
  ],
  'extensor_carpi_ulnaris': [
    'extensor_carpi_ulnaris_muscle',
  ],
  'extensor_digitorum': [
    'extensor_digitorum_muscle',
  ],
  'extensor_digiti_minimi': [
    'extensor_digiti_minimi_muscle',
  ],
  'rectus_abdominis': [
    'rectus_abdominis_muscle',
  ],
  'external_oblique': [
    'external_abdominal_oblique',
    'external_oblique_muscle',
  ],
  'internal_oblique': [
    'internal_abdominal_oblique',
    'internal_oblique_muscle',
  ],
  'transversus_abdominis': [
    'transversus_abdominis_muscle',
  ],
  'psoas_major': [
    'psoas_major_muscle',
    'psoas_muscle',
  ],
  'iliacus': [
    'iliacus_muscle',
  ],
  'quadratus_lumborum': [
    'quadratus_lumborum_muscle',
  ],
  'multifidus': [
    'multifidus_lumborum',
    'multifidus_thoracis',
    'multifidus_colli_muscle',
  ],
  'iliocostalis_lumborum': [
    'iliocostalis_lumborum_muscle',
  ],
  'iliocostalis_thoracis': [
    'iliocostalis_thoracis_muscle',
  ],
  'iliocostalis_cervicis': [
    'iliocostalis_colli_muscle',
    'iliocostalis_cervicis_muscle',
  ],
  'longissimus_thoracis': [
    'longissimus_thoracis_muscle',
  ],
  'spinalis_thoracis': [
    'spinalis_thoracis_muscle',
  ],
  'gluteus_maximus': [
    'gluteus_maximus_muscle',
  ],
  'gluteus_medius': [
    'gluteus_medius_muscle',
  ],
  'gluteus_minimus': [
    'gluteus_minimus_muscle',
  ],
  'piriformis': [
    'piriformis_muscle',
  ],
  'gemellus_superior': [
    'superior_gemellus_muscle',
  ],
  'gemellus_inferior': [
    'inferior_gemellus_muscle',
  ],
  'quadratus_femoris': [
    'quadratus_femoris_muscle',
  ],
  'sartorius': [
    'sartorius_muscle',
  ],
  'pectineus': [
    'pectineus_muscle',
  ],
  'adductor_longus': [
    'adductor_longus',
  ],
  'adductor_brevis': [
    'adductor_brevis',
  ],
  'adductor_magnus': [
    'adductor_magnus',
  ],
  'adductor_minimus': [
    'adductor_minimus',
  ],
  'gracilis': [
    'gracilis_muscle',
  ],
  'rectus_femoris': [
    'rectus_femoris_muscle',
  ],
  'vastus_lateralis': [
    'vastus_lateralis_muscle',
  ],
  'vastus_medialis': [
    'vastus_medialis_muscle',
  ],
  'vastus_intermedius': [
    'vastus_intermedius_muscle',
  ],
  'biceps_femoris_long_head': [
    'long_head_of_biceps_femoris_muscle',
  ],
  'biceps_femoris_short_head': [
    'short_head_of_biceps_femoris_muscle',
  ],
  'semitendinosus': [
    'semitendinosus_muscle',
  ],
  'semimembranosus': [
    'semimembranosus_muscle',
  ],
  'tibialis_anterior': [
    'tibialis_anterior_muscle',
  ],
  'tibialis_posterior': [
    'tibialis_posterior_muscle',
  ],
  'gastrocnemius_lateral_head': [
    'lateral_head_of_gastrocnemius',
  ],
  'gastrocnemius_medial_head': [
    'medial_head_of_gastrocnemius',
  ],
  'soleus': [
    'soleus_muscle',
  ],
  'plantaris': [
    'plantaris_muscle',
  ],
  'sternocleidomastoid': [
    'sternocleidomastoid_muscle',
  ],
  'splenius_capitis': [
    'splenius_capitis_muscle',
  ],
  'splenius_cervicis': [
    'splenius_colli_muscle',
    'splenius_cervicis_muscle',
  ],
  'semispinalis_cervicis': [
    'semispinalis_colli_muscle',
  ],
  'semispinalis_thoracis': [
    'semispinalis_thoracis',
  ],
  'spinalis_cervicis': [
    'spinalis_colli_muscle',
  ],
  'spinalis_capitis': [
    'spinalis_capitis_muscle',
  ],
};
