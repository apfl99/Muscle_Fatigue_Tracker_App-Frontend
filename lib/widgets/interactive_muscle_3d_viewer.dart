import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
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
  static const String _primaryModelSrc =
      'assets/models/human_muscular_system_segmented.glb';
  static const String _secondaryModelSrc =
      'assets/models/human_muscular_system.glb';
  static const String _fallbackModelSrc =
      'https://raw.githubusercontent.com/msorkhpar/3d-human-model-vite/main/body.glb';
  static const bool _enableE2eStub = bool.fromEnvironment(
    'MUSCLECARE_E2E_STUB_3D',
  );
  static const String _defaultOrbit = '0deg 84deg 108%';

  WebViewController? _webViewController;
  Timer? _runtimeSyncTimer;
  Timer? _autoFocusResetTimer;
  bool _modelReady = false;
  int _reloadNonce = 0;
  int _runtimeAttempt = 0;
  int _modelSourceIndex = 0;
  String? _lastAppliedPayloadJson;
  String _cameraOrbit = _defaultOrbit;

  List<String> get _modelSourceCandidates => const [
        _primaryModelSrc,
        _secondaryModelSrc,
        _fallbackModelSrc,
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

    final payloadChanged = _buildRuntimePayloadJson() !=
        _buildRuntimePayloadJson(fromWidget: oldWidget);
    if (payloadChanged) {
      _queueRuntimeSync(force: true);
    }

    final targetChanged =
        _canonicalizeMuscleCode(oldWidget.autoFocusTargetMuscleCode) !=
                _canonicalizeMuscleCode(widget.autoFocusTargetMuscleCode) ||
            oldWidget.enableAutoFocusIntro != widget.enableAutoFocusIntro;
    if (targetChanged) {
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
    if (payloadJson != null && payloadJson.isNotEmpty) {
      _queueRuntimeSync(forcedPayloadJson: payloadJson, force: true);
    }
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
    final introOrbit = _orbitByMuscle[targetCode] ?? _defaultOrbit;
    _cameraOrbit = introOrbit;
    _autoFocusResetTimer = Timer(const Duration(milliseconds: 2100), () {
      if (!mounted || !widget.interactive) {
        return;
      }
      setState(() {
        _cameraOrbit = _defaultOrbit;
      });
    });
  }

  void _retryModelLoad({bool advanceSource = false}) {
    _runtimeSyncTimer?.cancel();
    _autoFocusResetTimer?.cancel();
    setState(() {
      _modelReady = false;
      _runtimeAttempt = 0;
      _lastAppliedPayloadJson = null;
      if (advanceSource &&
          _modelSourceIndex < _modelSourceCandidates.length - 1) {
        _modelSourceIndex += 1;
      }
      _reloadNonce += 1;
    });
    _applyInitialAutoFocus();
  }

  void _queueRuntimeSync({
    String? forcedPayloadJson,
    bool force = false,
  }) {
    if (_enableE2eStub) {
      return;
    }
    _runtimeSyncTimer?.cancel();
    _runtimeSyncTimer = Timer(const Duration(milliseconds: 80), () async {
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
        if (mounted) {
          setState(() {
            _modelReady = false;
          });
        }
      }
    });
  }

  String _buildRuntimePayloadJson({
    InteractiveMuscle3DViewer? fromWidget,
  }) {
    final targetWidget = fromWidget ?? widget;
    final muscleStates = _buildMuscleStates(targetWidget);
    return jsonEncode({
      'highlighted':
          _canonicalizeMuscleCode(targetWidget.highlightedMuscleCode),
      'recommended':
          _canonicalizeMuscleCode(targetWidget.recommendedMuscleCode),
      'muscles': muscleStates,
    });
  }

  Map<String, Map<String, dynamic>> _buildMuscleStates(
    InteractiveMuscle3DViewer source,
  ) {
    final states = <String, _MuscleState>{};
    for (final entry in source.entries) {
      final code = _canonicalizeMuscleCode(entry.muscleCode);
      if (code == null || code.isEmpty) {
        continue;
      }
      final existing = states[code];
      final next = _MuscleState.fromEntry(entry);
      states[code] = existing == null ? next : existing.merge(next);
    }

    final highlighted = _canonicalizeMuscleCode(source.highlightedMuscleCode);
    if (highlighted != null && highlighted.isNotEmpty) {
      states[highlighted] = (states[highlighted] ?? _MuscleState.unknown())
          .copyWith(focused: true);
    }

    final recommended = _canonicalizeMuscleCode(source.recommendedMuscleCode);
    if (recommended != null && recommended.isNotEmpty) {
      states[recommended] = (states[recommended] ?? _MuscleState.unknown())
          .copyWith(recommended: true);
    }

    _mergeSyntheticState(
      states,
      'upper_arm_region',
      const ['biceps', 'triceps'],
    );
    _mergeSyntheticState(
      states,
      'forearm_region',
      const ['forearm_flexor', 'forearm_extensor', 'brachioradialis'],
    );
    _mergeSyntheticState(
      states,
      'shoulder_region',
      const ['front_deltoid', 'lateral_deltoid', 'rear_deltoid'],
    );

    return states.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
  }

  void _mergeSyntheticState(
    Map<String, _MuscleState> states,
    String targetCode,
    List<String> sourceCodes,
  ) {
    _MuscleState? merged;
    for (final sourceCode in sourceCodes) {
      final next = states[sourceCode];
      if (next == null) {
        continue;
      }
      merged = merged == null ? next : merged.merge(next);
    }
    if (merged == null) {
      return;
    }
    final existing = states[targetCode];
    states[targetCode] = existing == null ? merged : existing.merge(merged);
  }

  void _handleModelReadyMessage(String message) {
    if (!mounted) {
      return;
    }
    if (message.startsWith('error:')) {
      if (_modelSourceIndex < _modelSourceCandidates.length - 1) {
        _retryModelLoad(advanceSource: true);
        return;
      }
      setState(() {
        _runtimeAttempt = (_runtimeAttempt + 1).clamp(1, 999);
      });
      return;
    }
    if (message.startsWith('retry:')) {
      final retryCount = int.tryParse(message.split(':').last) ?? 0;
      if (retryCount >= 18 &&
          _modelSourceIndex < _modelSourceCandidates.length - 1) {
        _retryModelLoad(advanceSource: true);
        return;
      }
      setState(() {
        _runtimeAttempt = retryCount;
      });
      return;
    }
    if (message == 'ready') {
      setState(() {
        _modelReady = true;
        _runtimeAttempt = 0;
      });
      _queueRuntimeSync(force: true);
    }
  }

  void _handleTapMessage(String message) {
    final muscleCode = _canonicalizeMuscleCode(message);
    if (muscleCode == null || muscleCode.isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    widget.onMuscleTap?.call(muscleCode);
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
          if (_enableE2eStub)
            _buildE2eStub(primaryState)
          else
            _buildLiveViewer(context),
          _buildEdgeGlow(),
          _buildStatusOverlay(context),
        ],
      ),
    );
  }

  Widget _buildLiveViewer(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ModelViewer(
          key: ValueKey(
            'interactive_muscle_3d_viewer_${_modelSourceIndex}_$_reloadNonce',
          ),
          src: _activeModelSrc,
          id: 'musclecare-viewer',
          backgroundColor: Colors.transparent,
          cameraControls: widget.interactive,
          disablePan: true,
          disableZoom: true,
          disableTap: !widget.interactive,
          touchAction: TouchAction.none,
          autoRotate: widget.interactive ? widget.autoRotate : false,
          autoRotateDelay: 1800,
          rotationPerSecond: '12deg',
          cameraOrbit: _cameraOrbit,
          cameraTarget: '0m 0.02m 0m',
          fieldOfView: '32deg',
          minCameraOrbit: 'auto 72deg 82%',
          maxCameraOrbit: 'auto 108deg 130%',
          interpolationDecay: 160,
          environmentImage: 'neutral',
          exposure: 1.5,
          shadowSoftness: 1.0,
          loading: Loading.eager,
          reveal: Reveal.auto,
          interactionPrompt: InteractionPrompt.none,
          debugLogging: false,
          relatedCss: _buildViewerCss(),
          relatedJs: _buildViewerJs(),
          innerModelViewerHtml:
              widget.showHotspots ? _buildHotspotMarkup() : null,
          javascriptChannels: {
            JavascriptChannel(
              'ModelReady',
              onMessageReceived: (message) =>
                  _handleModelReadyMessage(message.message),
            ),
            JavascriptChannel(
              'TapChannel',
              onMessageReceived: (message) =>
                  _handleTapMessage(message.message),
            ),
          },
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
        ),
        if (!_modelReady) _buildLoadingOverlay(context),
      ],
    );
  }

  Widget _buildE2eStub(_MuscleState? primaryState) {
    final targetCode = _canonicalizeMuscleCode(
          widget.highlightedMuscleCode ??
              widget.recommendedMuscleCode ??
              'chest',
        ) ??
        'chest';
    final accent =
        _statusAccentColor(primaryState?.status ?? HeatmapStatus.green);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius - 8),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.05),
              accent.withValues(alpha: 0.12),
            ],
          ),
        ),
        child: Center(
          child: GestureDetector(
            key: const Key('e2e_stub_muscle_map'),
            onTap: () => widget.onMuscleTap?.call(targetCode),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 160,
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
                border: Border.all(color: accent.withValues(alpha: 0.32)),
              ),
              child: Text(
                '3D Stub',
                style: AppTheme.titleLargeStyle.copyWith(fontSize: 18),
              ),
            ),
          ),
        ),
      ),
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
                      onPressed: _retryModelLoad,
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

  Widget _buildStatusOverlay(BuildContext context) {
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
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
    final states = _buildMuscleStates(widget);
    final highlighted = _canonicalizeMuscleCode(widget.highlightedMuscleCode);
    if (highlighted != null) {
      final highlightedState = states[highlighted];
      if (highlightedState != null) {
        return _MuscleState.fromJson(highlightedState);
      }
    }
    final recommended = _canonicalizeMuscleCode(widget.recommendedMuscleCode);
    if (recommended != null) {
      final recommendedState = states[recommended];
      if (recommendedState != null) {
        return _MuscleState.fromJson(recommendedState);
      }
    }
    if (states.isEmpty) {
      return null;
    }
    final sorted = states.values.map(_MuscleState.fromJson).toList()
      ..sort((a, b) {
        final scoreA = a.visualPriority;
        final scoreB = b.visualPriority;
        return scoreB.compareTo(scoreA);
      });
    return sorted.isEmpty ? null : sorted.first;
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

  String _buildViewerCss() {
    return '''
      :host {
        --progress-mask: transparent;
      }

      model-viewer {
        width: 100%;
        height: 100%;
        background:
          radial-gradient(circle at 50% 8%, rgba(83, 255, 174, 0.10), transparent 38%),
          radial-gradient(circle at 50% 100%, rgba(19, 29, 40, 0.95), rgba(8, 10, 15, 0.98));
        filter: contrast(1.18) saturate(1.08) brightness(1.02);
        cursor: grab;
      }

      model-viewer:active {
        cursor: grabbing;
      }

      .hotspot-chip {
        border: 1px solid rgba(255, 255, 255, 0.16);
        border-radius: 999px;
        padding: 4px 8px;
        background: rgba(9, 13, 18, 0.72);
        color: rgba(255, 255, 255, 0.92);
        font-size: 10px;
        font-family: Inter, sans-serif;
        letter-spacing: 0.02em;
        pointer-events: none;
        backdrop-filter: blur(8px);
      }
    ''';
  }

  String _buildHotspotMarkup() {
    return '''
      <div slot="hotspot-1" data-position="0m 0.4m 0.13m" class="hotspot-chip">CHEST</div>
      <div slot="hotspot-2" data-position="0m 0.15m 0.16m" class="hotspot-chip">ABS</div>
      <div slot="hotspot-3" data-position="-0.23m 0.18m 0.02m" class="hotspot-chip">FOREARM</div>
      <div slot="hotspot-4" data-position="0.12m -0.25m 0.08m" class="hotspot-chip">QUADS</div>
      <div slot="hotspot-5" data-position="0.1m -0.56m 0.03m" class="hotspot-chip">CALVES</div>
    ''';
  }

  String _buildViewerJs() {
    final muscleSignatureJson = jsonEncode(_muscleSignatures);
    final initialPayloadJson = _buildRuntimePayloadJson();
    return '''
      (() => {
        const runtimeState = {
          payload: $initialPayloadJson,
          materialToMuscle: new Map(),
          cameraThetaDeg: 0,
        };
        const muscleSignatures = $muscleSignatureJson;

        const viewer = document.querySelector('#musclecare-viewer');
        if (!viewer) {
          return;
        }

        const normalize = (value) => {
          return String(value || '')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '_')
            .replace(/_+/g, '_')
            .replace(/^_+|_+\$/g, '');
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

        const toDegrees = (value) => {
          const raw = String(value ?? '');
          const scalar = parseScalar(raw);
          if (!Number.isFinite(scalar)) {
            return 0;
          }
          if (raw.includes('deg')) {
            return scalar;
          }
          if (raw.includes('rad') || Math.abs(scalar) <= Math.PI * 2.1) {
            return scalar * (180 / Math.PI);
          }
          return scalar;
        };

        const normalizeTheta = (thetaDeg) => {
          const normalized = thetaDeg % 360;
          return normalized < 0 ? normalized + 360 : normalized;
        };

        const updateCameraTheta = () => {
          try {
            if (!viewer.getCameraOrbit) {
              return;
            }
            const orbit = viewer.getCameraOrbit();
            const theta = orbit && orbit.theta != null ? orbit.theta : orbit;
            runtimeState.cameraThetaDeg = normalizeTheta(toDegrees(theta));
          } catch (_) {}
        };

        const resolveFrontBack = (position, normal) => {
          const posZ = Number(position[2] || 0);
          const normalZ = Number(normal[2] || 0);
          if (posZ > 0.018 || normalZ > 0.22) {
            return 'front';
          }
          if (posZ < -0.018 || normalZ < -0.22) {
            return 'back';
          }
          const theta = normalizeTheta(runtimeState.cameraThetaDeg);
          if (theta <= 45 || theta >= 315) {
            return 'front';
          }
          if (theta >= 135 && theta <= 225) {
            return 'back';
          }
          return theta < 180 ? 'front' : 'back';
        };

        const colors = {
          neutral: [0.18, 0.22, 0.27],
          green: [0.20, 0.98, 0.56],
          yellow: [1.00, 0.78, 0.28],
          red: [1.00, 0.32, 0.46],
          focus: [0.55, 1.00, 0.76],
          recommend: [0.24, 0.92, 1.00],
        };

        const resolveMuscle = (signature) => {
          const normalized = normalize(signature);
          if (!normalized) {
            return null;
          }
          for (const [muscleCode, signatures] of Object.entries(muscleSignatures)) {
            for (const candidate of signatures) {
              const normalizedCandidate = normalize(candidate);
              if (!normalizedCandidate) {
                continue;
              }
              if (
                normalized === normalizedCandidate ||
                normalized.includes(normalizedCandidate) ||
                normalizedCandidate.includes(normalized)
              ) {
                return muscleCode;
              }
            }
          }
          return null;
        };

        const resolveTapVariant = (baseMuscle, position, normal) => {
          if (!baseMuscle) {
            return null;
          }
          if (baseMuscle === 'upper_arm_region') {
            return resolveFrontBack(position, normal) === 'front'
              ? 'biceps'
              : 'triceps';
          }
          if (baseMuscle === 'forearm_region') {
            return resolveFrontBack(position, normal) === 'front'
              ? 'forearm_flexor'
              : 'forearm_extensor';
          }
          if (baseMuscle === 'shoulder_region') {
            const posZ = Number(position[2] || 0);
            const normalZ = Number(normal[2] || 0);
            if (posZ > 0.03 || normalZ > 0.28) {
              return 'front_deltoid';
            }
            if (posZ < -0.03 || normalZ < -0.28) {
              return 'rear_deltoid';
            }
            return 'lateral_deltoid';
          }
          return baseMuscle;
        };

        const resolveMaterialState = (muscleCode) => {
          const payload = runtimeState.payload || {};
          const muscles = payload.muscles || {};
          const state = muscles[muscleCode] || {};
          return {
            muscleCode,
            status: state.status || 'unknown',
            intensity: Number(state.intensity || 0.26),
            focused: Boolean(state.focused),
            recommended: Boolean(state.recommended),
          };
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

          let mix = 0.24 + Math.min(Math.max(state.intensity, 0.0), 1.0) * 0.44;
          if (state.focused) {
            base = colors.focus;
            mix += 0.22;
          } else if (state.recommended) {
            base = colors.recommend;
            mix += 0.14;
          }
          mix = Math.min(mix, 0.86);

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
          material.pbrMetallicRoughness.setRoughnessFactor(
            state.focused || state.recommended ? 0.30 : 0.68,
          );
          material.pbrMetallicRoughness.setMetallicFactor(
            state.focused || state.recommended ? 0.60 : 0.18,
          );
          if (material.setEmissiveFactor) {
            material.setEmissiveFactor(emissive);
          }
        };

        const buildMaterialIndex = () => {
          runtimeState.materialToMuscle.clear();
          if (!viewer.model || !Array.isArray(viewer.model.materials)) {
            return false;
          }
          let indexed = 0;
          for (const material of viewer.model.materials) {
            const materialName = material && material.name ? material.name : '';
            const muscleCode = resolveMuscle(materialName);
            if (muscleCode) {
              runtimeState.materialToMuscle.set(normalize(materialName), muscleCode);
              indexed += 1;
            }
          }
          return indexed > 0;
        };

        const applyAllMaterials = () => {
          if (!viewer.model || !Array.isArray(viewer.model.materials)) {
            return false;
          }
          if (runtimeState.materialToMuscle.size === 0) {
            buildMaterialIndex();
          }
          for (const material of viewer.model.materials) {
            const normalizedName = normalize(material && material.name ? material.name : '');
            const muscleCode =
              runtimeState.materialToMuscle.get(normalizedName) ||
              resolveMuscle(normalizedName);
            if (muscleCode) {
              applyAppearance(material, muscleCode);
              runtimeState.materialToMuscle.set(normalizedName, muscleCode);
            } else {
              material.pbrMetallicRoughness.setBaseColorFactor([
                colors.neutral[0],
                colors.neutral[1],
                colors.neutral[2],
                1.0,
              ]);
              material.pbrMetallicRoughness.setRoughnessFactor(0.78);
              material.pbrMetallicRoughness.setMetallicFactor(0.10);
              if (material.setEmissiveFactor) {
                material.setEmissiveFactor([0.0, 0.0, 0.0]);
              }
            }
          }
          return true;
        };

        const resolveHitContext = (x, y) => {
          let materialName = '';
          let nodeName = '';
          let surfaceName = '';
          let pointData = null;
          try {
            const material = viewer.materialFromPoint ? viewer.materialFromPoint(x, y) : null;
            materialName = material && material.name ? material.name : '';
          } catch (_) {}
          try {
            const model = viewer.model || null;
            const node =
              model && model.nodeFromPoint
                ? model.nodeFromPoint(x, y)
                : viewer.nodeFromPoint
                  ? viewer.nodeFromPoint(x, y)
                  : null;
            nodeName = node && node.name ? node.name : '';
          } catch (_) {}
          try {
            const surface = viewer.surfaceFromPoint ? viewer.surfaceFromPoint(x, y) : null;
            surfaceName = surface ? String(surface) : '';
          } catch (_) {}
          try {
            pointData = viewer.positionAndNormalFromPoint
              ? viewer.positionAndNormalFromPoint(x, y)
              : null;
          } catch (_) {}
          return {
            materialName,
            nodeName,
            surfaceName,
            position: parseVector(pointData && pointData.position),
            normal: parseVector(pointData && pointData.normal),
          };
        };

        const scheduleReadyProbe = (attempt = 0) => {
          if (!viewer) {
            return;
          }
          const ready = applyAllMaterials();
          if (ready) {
            viewer.setAttribute('shadow-intensity', '1');
            viewer.setAttribute('shadow-softness', '1');
            viewer.setAttribute('exposure', '1.5');
            ModelReady.postMessage('ready');
            return;
          }
          const nextAttempt = attempt + 1;
          ModelReady.postMessage('retry:' + nextAttempt);
          if (nextAttempt < 40) {
            window.setTimeout(() => scheduleReadyProbe(nextAttempt), 250);
          } else {
            ModelReady.postMessage('error:materials_unavailable');
          }
        };

        const resolveTapMuscle = (event) => {
          if (!event || !viewer) {
            return null;
          }
          const rect = viewer.getBoundingClientRect();
          const x = event.clientX - rect.left;
          const y = event.clientY - rect.top;
          const hit = resolveHitContext(x, y);
          const fromNode = resolveMuscle(hit.nodeName);
          const fromMaterial = resolveMuscle(hit.materialName);
          const fromSurface = resolveMuscle(hit.surfaceName);
          return resolveTapVariant(
            fromNode || fromMaterial || fromSurface,
            hit.position,
            hit.normal,
          );
        };

        window.applyMusclecareRuntime = (payload) => {
          runtimeState.payload = payload || {};
          applyAllMaterials();
        };

        viewer.addEventListener('camera-change', updateCameraTheta);
        viewer.addEventListener('load', () => {
          updateCameraTheta();
          scheduleReadyProbe(0);
        });
        viewer.addEventListener('scene-graph-ready', () => {
          updateCameraTheta();
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

        updateCameraTheta();
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

  factory _MuscleState.fromJson(Map<String, dynamic> json) {
    final rawStatus = '${json['status'] ?? 'unknown'}';
    final rawIntensity = (json['intensity'] as num?)?.toDouble() ?? 0.24;
    return _MuscleState(
      status: HeatmapStatusParser.fromRaw(rawStatus),
      intensity: rawIntensity,
      focused: json['focused'] == true,
      recommended: json['recommended'] == true,
    );
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
  final normalized = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-/\.]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.isEmpty) {
    return null;
  }
  final compact = normalized
      .split('_')
      .where((token) => token.isNotEmpty && !_sideTokens.contains(token))
      .join('_');
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
  'bilateral',
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
  'traps': 'trapezius',
  'upper_trap': 'upper_trapezius',
  'middle_trap': 'middle_trapezius',
  'lower_trap': 'lower_trapezius',
  'rhomboid': 'rhomboids',
  'biceps_brachii': 'biceps',
  'triceps_brachii': 'triceps',
  'upper_arm': 'upper_arm_region',
  'upper_arms': 'upper_arm_region',
  'upperarms': 'upper_arm_region',
  'forearm': 'forearm_flexor',
  'forearms': 'forearm_flexor',
  'fore_arm': 'forearm_region',
  'fore_arms': 'forearm_region',
  'forearm_region': 'forearm_region',
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
};

const Map<String, String> _orbitByMuscle = {
  'chest': '0deg 82deg 102%',
  'rectus_abdominis': '0deg 88deg 106%',
  'obliques': '18deg 88deg 108%',
  'front_deltoid': '22deg 84deg 106%',
  'lateral_deltoid': '52deg 84deg 108%',
  'rear_deltoid': '210deg 86deg 108%',
  'upper_arm_region': '54deg 86deg 108%',
  'biceps': '54deg 82deg 105%',
  'triceps': '228deg 84deg 108%',
  'forearm_region': '64deg 92deg 114%',
  'forearm_flexor': '64deg 90deg 112%',
  'forearm_extensor': '246deg 92deg 112%',
  'latissimus': '212deg 84deg 109%',
  'trapezius': '180deg 74deg 108%',
  'rhomboids': '186deg 82deg 110%',
  'gluteus_maximus': '180deg 90deg 104%',
  'quadriceps': '0deg 94deg 112%',
  'hamstrings': '180deg 94deg 114%',
  'calves': '180deg 102deg 120%',
  'gastrocnemius': '180deg 102deg 118%',
  'tibialis_anterior': '0deg 100deg 118%',
};

const Map<String, List<String>> _muscleSignatures = {
  'upper_arm_region': [
    'upper_arm_region',
    'upper_arm',
    'upper_arms',
    'upperarms',
    'material_upperarms',
    '10_upper_arms',
  ],
  'forearm_region': [
    'forearm_region',
    'fore_arm',
    'fore_arms',
    'forearms',
    'material_forearms',
    '12_fore_arms',
  ],
  'shoulder_region': [
    'shoulder_region',
    'shoulders',
    'material_shoulders',
    '04_shoulders',
  ],
  'chest': [
    'chest',
    'pec',
    'pectoralis',
    'pectoral',
    'torso_front_upper',
  ],
  'upper_chest': [
    'upper_chest',
    'clavicular_pec',
    'pectoralis_clavicular',
  ],
  'serratus_anterior': [
    'serratus',
    'serratus_anterior',
  ],
  'front_deltoid': [
    'front_deltoid',
    'anterior_deltoid',
    'anterior_delt',
    'deltoid_front',
  ],
  'lateral_deltoid': [
    'lateral_deltoid',
    'middle_deltoid',
    'side_deltoid',
    'lateral_delt',
  ],
  'rear_deltoid': [
    'rear_deltoid',
    'posterior_deltoid',
    'posterior_delt',
  ],
  'trapezius': [
    'trapezius',
    'trap',
    'traps',
  ],
  'upper_trapezius': [
    'upper_trapezius',
    'upper_trap',
  ],
  'middle_trapezius': [
    'middle_trapezius',
    'middle_trap',
  ],
  'lower_trapezius': [
    'lower_trapezius',
    'lower_trap',
  ],
  'rhomboids': [
    'rhomboid',
    'rhomboids',
  ],
  'latissimus': [
    'latissimus',
    'lats',
    'latissimus_dorsi',
  ],
  'teres_major': [
    'teres_major',
    'teresmajor',
  ],
  'teres_minor': [
    'teres_minor',
    'teresminor',
  ],
  'infraspinatus': [
    'infraspinatus',
  ],
  'supraspinatus': [
    'supraspinatus',
  ],
  'erector_spinae': [
    'erector_spinae',
    'spinal_erector',
    'erectors',
  ],
  'lower_back': [
    'lower_back',
    'lumbar',
  ],
  'biceps': [
    'biceps',
    'biceps_brachii',
    'material_biceps',
  ],
  'brachialis': [
    'brachialis',
  ],
  'triceps': [
    'triceps',
    'triceps_brachii',
    'material_triceps',
  ],
  'brachioradialis': [
    'brachioradialis',
  ],
  'forearm_flexor': [
    'forearm_flexor',
    'forearm_flexors',
    'wrist_flexor',
    'flexor',
    'forearm_anterior',
    'material_forearmflexor',
  ],
  'forearm_extensor': [
    'forearm_extensor',
    'forearm_extensors',
    'wrist_extensor',
    'extensor',
    'forearm_posterior',
    'material_forearmextensor',
  ],
  'rectus_abdominis': [
    'rectus_abdominis',
    'abdominal',
    'abs',
    'abdomen',
  ],
  'transverse_abdominis': [
    'transverse_abdominis',
    'transversus_abdominis',
  ],
  'obliques': [
    'oblique',
    'obliques',
    'external_oblique',
    'internal_oblique',
  ],
  'hip_flexors': [
    'hip_flexor',
    'iliopsoas',
    'psoas',
  ],
  'gluteus_maximus': [
    'gluteus_maximus',
    'glute_maximus',
    'gluteus',
    'glutes',
  ],
  'gluteus_medius': [
    'gluteus_medius',
    'glute_medius',
  ],
  'gluteus_minimus': [
    'gluteus_minimus',
    'glute_minimus',
  ],
  'adductors': [
    'adductor',
    'adductors',
    'inner_thigh',
  ],
  'abductors': [
    'abductor',
    'abductors',
    'outer_hip',
  ],
  'quadriceps': [
    'quadriceps',
    'quads',
  ],
  'rectus_femoris': [
    'rectus_femoris',
  ],
  'vastus_lateralis': [
    'vastus_lateralis',
  ],
  'vastus_medialis': [
    'vastus_medialis',
  ],
  'vastus_intermedius': [
    'vastus_intermedius',
  ],
  'hamstrings': [
    'hamstrings',
    'hamstring',
  ],
  'biceps_femoris': [
    'biceps_femoris',
  ],
  'semitendinosus': [
    'semitendinosus',
  ],
  'semimembranosus': [
    'semimembranosus',
  ],
  'calves': [
    'calves',
    'calf',
  ],
  'gastrocnemius': [
    'gastrocnemius',
    'gastroc',
  ],
  'soleus': [
    'soleus',
  ],
  'tibialis_anterior': [
    'tibialis_anterior',
    'tibialis',
    'shin',
  ],
  'neck': [
    'neck',
    'sternocleidomastoid',
  ],
};
