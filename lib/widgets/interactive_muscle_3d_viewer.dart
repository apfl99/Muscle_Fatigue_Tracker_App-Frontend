import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../features/heatmap/model/muscle_taxonomy.dart';
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

class _InteractiveMuscle3DViewerState extends State<InteractiveMuscle3DViewer>
    with WidgetsBindingObserver {
  static const String _localSegmentedModelSrc =
      'assets/models/human_muscular_system_segmented.glb';
  static const String _localModelViewerJsSrc = 'assets/js/model-viewer.min.js';
  static const String _viewerId = 'musclecare-anatomy-viewer';
  static const String _defaultOrbit = '0deg 90deg 112%';
  static const Duration _modelLoadTimeout = Duration(milliseconds: 10000);
  static const String _timeoutFallbackMessage = '3D 모델을 불러올 수 없습니다';
  static const String _genericLoadFailureMessage = '3D 모델을 불러올 수 없습니다';
  static final Map<String, String> _offlineHtmlCache = <String, String>{};
  static final Map<String, Future<String>> _modelDataUriCache =
      <String, Future<String>>{};
  static Future<String>? _modelViewerJsInlineCache;

  InAppWebViewController? _webViewController;
  Timer? _runtimeSyncTimer;
  Timer? _autoFocusResetTimer;
  Timer? _modelLoadTimeoutTimer;
  Timer? _webViewReadyProbeTimer;
  bool _webViewReadyProbeBusy = false;
  int _webViewReadyProbeAttempt = 0;
  DateTime? _loadSessionStartedAt;
  DateTime? _lifecyclePausedAt;
  bool _modelReady = false;
  int _runtimeAttempt = 0;
  int _modelSourceIndex = 0;
  int _reloadNonce = 0;
  String? _lastAppliedPayloadJson;
  String? _blockingErrorMessage;
  String _cameraOrbit = _defaultOrbit;

  List<String> get _modelSourceCandidates => const [
        _localSegmentedModelSrc,
      ];

  String get _activeModelSrc => _modelSourceCandidates[_modelSourceIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_handleExternalControllerChanged);
    widget.controller?.bindCameraOrbit(_setCameraOrbitFromController);
    _applyInitialAutoFocus();
    _startModelLoadTimeoutWatchdog();
    unawaited(_loadOfflineViewerHtml(forceRebuild: true));
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
    final entriesChanged = _buildEntriesDigest(oldWidget.entries) !=
        _buildEntriesDigest(widget.entries);
    if (entriesChanged || previousPayload != nextPayload) {
      _queueRuntimeSync(forcedPayloadJson: nextPayload, force: true);
    }

    final oldTarget =
        _canonicalizeMuscleCode(oldWidget.autoFocusTargetMuscleCode);
    final nextTarget =
        _canonicalizeMuscleCode(widget.autoFocusTargetMuscleCode);
    if (oldTarget != nextTarget ||
        oldWidget.enableAutoFocusIntro != widget.enableAutoFocusIntro) {
      _applyInitialAutoFocus();
    }

    if (oldWidget.interactive != widget.interactive ||
        oldWidget.autoRotate != widget.autoRotate) {
      unawaited(_loadOfflineViewerHtml(forceRebuild: true));
    }
  }

  @override
  void dispose() {
    _runtimeSyncTimer?.cancel();
    _autoFocusResetTimer?.cancel();
    _modelLoadTimeoutTimer?.cancel();
    _webViewReadyProbeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?.removeListener(_handleExternalControllerChanged);
    widget.controller?.unbindCameraOrbit(_setCameraOrbitFromController);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[3DViewer] lifecycle=$state ready=$_modelReady source=$_activeModelSrc',
      );
    }
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _lifecyclePausedAt;
      if (pausedAt != null && _loadSessionStartedAt != null) {
        final pausedFor = DateTime.now().difference(pausedAt);
        _loadSessionStartedAt = _loadSessionStartedAt!.add(pausedFor);
      }
      _lifecyclePausedAt = null;
      if (_modelReady) {
        _queueRuntimeSync(force: true);
      } else if (_blockingErrorMessage == null) {
        _startModelLoadTimeoutWatchdog(preserveTimeoutWindow: true);
        _scheduleWebViewReadyProbe(resetAttempt: false);
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _lifecyclePausedAt ??= DateTime.now();
      _modelLoadTimeoutTimer?.cancel();
      _modelLoadTimeoutTimer = null;
      _webViewReadyProbeTimer?.cancel();
      _webViewReadyProbeTimer = null;
      _webViewReadyProbeBusy = false;
    }
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
    unawaited(_syncCameraOrbitToViewer());
  }

  void _handleWebViewCreated(InAppWebViewController controller) {
    final hadController = _webViewController != null;
    _webViewController = controller;
    if (!mounted) {
      return;
    }
    if (hadController || _modelReady || _blockingErrorMessage != null) {
      setState(() {
        _modelReady = false;
        _runtimeAttempt = 0;
        _blockingErrorMessage = null;
        _lastAppliedPayloadJson = null;
      });
    }
    if (_lifecyclePausedAt != null) {
      return;
    }
    _startModelLoadTimeoutWatchdog();
    _scheduleWebViewReadyProbe();
  }

  bool _isOfflineSafeRequest(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'about:blank' ||
        normalized.startsWith('data:') ||
        normalized.startsWith('blob:') ||
        normalized.startsWith('javascript:') ||
        normalized.startsWith('file:') ||
        normalized.startsWith('flutter-assets:')) {
      return true;
    }
    return false;
  }

  Future<void> _loadOfflineViewerHtml({bool forceRebuild = false}) async {
    final controller = _webViewController;
    if (controller == null || !mounted) {
      return;
    }
    final cacheKey = _activeModelSrc;
    final cachedHtml = !forceRebuild ? _offlineHtmlCache[cacheKey] : null;
    if (cachedHtml != null) {
      await controller.loadData(
        data: cachedHtml,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
        historyUrl: WebUri('about:blank'),
      );
      return;
    }
    try {
      final modelViewerJsContent = await _loadModelViewerJsInline();
      final modelDataUri = await _loadModelDataUri(_activeModelSrc);
      final html = _buildOfflineViewerHtml(
        jsContent: modelViewerJsContent,
        modelDataUri: modelDataUri,
      );
      _offlineHtmlCache[cacheKey] = html;
      if (!mounted) {
        return;
      }
      await controller.loadData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
        historyUrl: WebUri('about:blank'),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _setBlockingErrorMessage(_genericLoadFailureMessage);
    }
  }

  Future<String> _loadModelViewerJsInline() {
    return _modelViewerJsInlineCache ??=
        rootBundle.loadString(_localModelViewerJsSrc);
  }

  Future<String> _loadModelDataUri(String modelAssetPath) {
    return _modelDataUriCache.putIfAbsent(modelAssetPath, () async {
      final modelBytesData = await rootBundle.load(modelAssetPath);
      final modelBytes = modelBytesData.buffer.asUint8List(
        modelBytesData.offsetInBytes,
        modelBytesData.lengthInBytes,
      );
      return 'data:model/gltf-binary;base64,${base64Encode(modelBytes)}';
    });
  }

  String _buildOfflineViewerHtml({
    required String jsContent,
    required String modelDataUri,
  }) {
    const htmlEscape = HtmlEscape(HtmlEscapeMode.element);
    final escapedId = htmlEscape.convert(_viewerId);
    final escapedModelDataUri = htmlEscape.convert(modelDataUri);
    final escapedCameraOrbit = htmlEscape.convert(_cameraOrbit);
    final escapedRotation =
        htmlEscape.convert(widget.autoRotate ? '20deg' : '0deg');
    final escapedDisableTap = widget.interactive ? '' : 'disable-tap';
    const escapedDisableZoom = 'disable-zoom';
    const escapedDisablePan = 'disable-pan';
    final escapedTouchAction = widget.interactive ? 'none' : 'auto';
    final escapedAutoRotate = widget.interactive && widget.autoRotate
        ? 'auto-rotate auto-rotate-delay="1400"'
        : '';
    final escapedCss = _buildViewerCss();
    final escapedRuntimeJs = _buildViewerJs();
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <meta http-equiv="Content-Security-Policy" content="default-src * data: blob: 'unsafe-inline' 'unsafe-eval'; script-src * data: blob: 'unsafe-inline' 'unsafe-eval'; style-src * data: blob: 'unsafe-inline'; img-src * data: blob: 'unsafe-inline'; media-src * data: blob: 'unsafe-inline'; connect-src * data: blob: 'unsafe-inline'; worker-src * data: blob: 'unsafe-inline'; font-src * data: blob: 'unsafe-inline';">
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: transparent;
      touch-action: $escapedTouchAction;
    }
    $escapedCss
  </style>
  <script type="module">
$jsContent
  </script>
</head>
<body>
  <model-viewer
    id="$escapedId"
    src="$escapedModelDataUri"
    background-color="transparent"
    camera-controls
    loading="eager"
    reveal="auto"
    interaction-prompt="none"
    camera-orbit="$escapedCameraOrbit"
    camera-target="auto auto auto"
    field-of-view="auto"
    min-camera-orbit="auto 5deg auto"
    max-camera-orbit="auto 175deg auto"
    orbit-sensitivity="1.5"
    rotation-per-second="$escapedRotation"
    interpolation-decay="20"
    exposure="1.2"
    shadow-intensity="4.4"
    shadow-softness="0.8"
    $escapedDisableTap
    $escapedDisableZoom
    $escapedDisablePan
    $escapedAutoRotate>
  </model-viewer>
  <script>
$escapedRuntimeJs
  </script>
</body>
</html>
''';
  }

  Future<void> _syncCameraOrbitToViewer() async {
    if (!_modelReady || _webViewController == null) {
      return;
    }
    final escapedOrbit = jsonEncode(_cameraOrbit);
    try {
      await _webViewController!.evaluateJavascript(
        source: '''(() => {
  const viewer = document.querySelector('#$_viewerId') || document.querySelector('model-viewer');
  if (!viewer) return;
  viewer.cameraOrbit = JSON.parse($escapedOrbit);
  viewer.setAttribute('camera-orbit', JSON.parse($escapedOrbit));
})();''',
      );
    } catch (_) {}
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

  void _startModelLoadTimeoutWatchdog({bool preserveTimeoutWindow = false}) {
    _modelLoadTimeoutTimer?.cancel();
    final now = DateTime.now();
    if (!preserveTimeoutWindow || _loadSessionStartedAt == null) {
      _loadSessionStartedAt = now;
    }
    final elapsed = now.difference(_loadSessionStartedAt!);
    final remaining = _modelLoadTimeout - elapsed;
    if (remaining <= Duration.zero) {
      _setBlockingErrorMessage(_timeoutFallbackMessage);
      return;
    }
    _modelLoadTimeoutTimer = Timer(remaining, () {
      if (!mounted ||
          _modelReady ||
          _blockingErrorMessage != null ||
          _lifecyclePausedAt != null) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[3DViewer] timeout source=$_activeModelSrc index=$_modelSourceIndex',
        );
      }
      setState(() {
        _runtimeAttempt = (_runtimeAttempt + 1).clamp(1, 999);
        _blockingErrorMessage = _timeoutFallbackMessage;
      });
    });
  }

  void _clearModelLoadTimeoutWatchdog({bool resetSessionWindow = false}) {
    _modelLoadTimeoutTimer?.cancel();
    _modelLoadTimeoutTimer = null;
    if (resetSessionWindow) {
      _loadSessionStartedAt = null;
    }
  }

  void _setBlockingErrorMessage(String message) {
    _clearModelLoadTimeoutWatchdog();
    _cancelWebViewReadyProbe();
    if (!mounted) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[3DViewer] blocking_error="$message" source=$_activeModelSrc index=$_modelSourceIndex',
      );
    }
    setState(() {
      _runtimeAttempt = (_runtimeAttempt + 1).clamp(1, 999);
      _blockingErrorMessage = message;
    });
  }

  void _cancelWebViewReadyProbe() {
    _webViewReadyProbeTimer?.cancel();
    _webViewReadyProbeTimer = null;
    _webViewReadyProbeBusy = false;
    _webViewReadyProbeAttempt = 0;
  }

  void _scheduleWebViewReadyProbe({bool resetAttempt = true}) {
    _webViewReadyProbeTimer?.cancel();
    if (resetAttempt) {
      _webViewReadyProbeAttempt = 0;
    }
    _webViewReadyProbeBusy = false;
    _webViewReadyProbeTimer = Timer.periodic(
      const Duration(milliseconds: 850),
      (timer) async {
        if (!mounted || _modelReady || _blockingErrorMessage != null) {
          _cancelWebViewReadyProbe();
          return;
        }
        if (_lifecyclePausedAt != null) {
          return;
        }
        final controller = _webViewController;
        if (controller == null || _webViewReadyProbeBusy) {
          return;
        }
        _webViewReadyProbeBusy = true;
        _webViewReadyProbeAttempt += 1;
        try {
          final result = await controller.evaluateJavascript(
            source: '''(() => {
const findViewer = () => {
  const direct = document.querySelector('#$_viewerId') || document.querySelector('model-viewer');
  if (direct) return direct;
  const frames = Array.from(document.querySelectorAll('iframe'));
  for (const frame of frames) {
    try {
      const doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document);
      if (!doc) continue;
      const nested = doc.querySelector('#$_viewerId') || doc.querySelector('model-viewer');
      if (nested) return nested;
    } catch (_) {}
  }
  return null;
};
const viewer = findViewer();
if (!viewer) return 'missing';
const loaded = Boolean(viewer.loaded) || Boolean(viewer.model);
if (loaded) return 'ready';
const progress = Number(viewer.loadedProgress || 0);
if (progress >= 0.98) return 'ready';
if (progress > 0.0) return 'progress:' + progress.toFixed(2);
return 'present';
})();''',
          );
          final probe = result
              .toString()
              .replaceAll('"', '')
              .replaceAll("'", '')
              .trim()
              .toLowerCase();
          if (kDebugMode && _webViewReadyProbeAttempt <= 4) {
            debugPrint(
              '[3DViewerProbe] attempt=$_webViewReadyProbeAttempt result=$probe source=$_activeModelSrc',
            );
          }
          if (probe == 'ready') {
            _cancelWebViewReadyProbe();
            _handleModelReadyMessage('ready');
            return;
          }
        } catch (_) {
          // Swallow transient WebView evaluation errors during startup.
        } finally {
          _webViewReadyProbeBusy = false;
        }
        if (_webViewReadyProbeAttempt >= 18) {
          _cancelWebViewReadyProbe();
          _handleModelReadyMessage('error:viewer_not_ready');
        }
      },
    );
  }

  String _resolveLoadFailureMessage(String reason) {
    final normalized = reason.toLowerCase();
    if (normalized.contains('oom') ||
        normalized.contains('out_of_memory') ||
        normalized.contains('webgl_context_lost') ||
        normalized.contains('context_lost')) {
      return 'WebGL 메모리 부족으로 3D 렌더링에 실패했습니다. 다시 시도해주세요';
    }
    if (normalized.contains('scene_graph')) {
      return '3D 장면 초기화에 실패했습니다. 다시 시도해주세요';
    }
    return _genericLoadFailureMessage;
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
        await _webViewController!.evaluateJavascript(
          source: 'window.applyMusclecareRuntime && '
              'window.applyMusclecareRuntime(JSON.parse($escapedPayload));',
        );
      } catch (_) {
        if (!mounted) {
          return;
        }
        _setBlockingErrorMessage(_genericLoadFailureMessage);
      }
    });
  }

  void _retryModelLoad({
    bool advanceSource = false,
    bool resetAttempt = true,
    bool preserveTimeoutWindow = false,
  }) {
    _runtimeSyncTimer?.cancel();
    _autoFocusResetTimer?.cancel();
    _cancelWebViewReadyProbe();
    _clearModelLoadTimeoutWatchdog(
      resetSessionWindow: !preserveTimeoutWindow,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _modelReady = false;
      _blockingErrorMessage = null;
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
    _startModelLoadTimeoutWatchdog(
      preserveTimeoutWindow: preserveTimeoutWindow,
    );
    unawaited(
      _loadOfflineViewerHtml(
        forceRebuild: resetAttempt || advanceSource,
      ),
    );
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

    for (final muscleCode in canonicalDetailedMuscleCodes) {
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

  String _buildEntriesDigest(List<MuscleHeatmapEntry> entries) {
    final signatures = entries.map((entry) {
      final code = _canonicalizeMuscleCode(entry.muscleCode) ?? '';
      return '$code:${entry.status.rawValue}:${entry.fatigueScore.toStringAsFixed(4)}';
    }).toList()
      ..sort();
    return signatures.join('|');
  }

  List<String> _expandMuscleCode(String canonicalCode) {
    final resolved = _ssotAliasToCanonicalCode[canonicalCode] ?? canonicalCode;
    if (_ssotDetailedMeshSignatures.containsKey(resolved)) {
      return <String>[resolved];
    }
    return const <String>[];
  }

  String _resolveTapCode(String detailCode) {
    final canonical = _canonicalizeMuscleCode(detailCode);
    if (canonical == null || canonical.isEmpty) {
      return detailCode;
    }
    return _ssotTapOutputByDetailedCode[canonical] ?? canonical;
  }

  void _handleModelReadyMessage(String message) {
    if (!mounted) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[3DViewerBridge] message=$message source=$_activeModelSrc index=$_modelSourceIndex',
      );
    }
    if (message == 'ready') {
      _clearModelLoadTimeoutWatchdog(resetSessionWindow: true);
      _cancelWebViewReadyProbe();
      setState(() {
        _modelReady = true;
        _runtimeAttempt = 0;
        _blockingErrorMessage = null;
      });
      _queueRuntimeSync(force: true);
      unawaited(_syncCameraOrbitToViewer());
      return;
    }
    if (message.startsWith('retry:')) {
      final retryCount = int.tryParse(message.split(':').last) ?? 0;
      if (_runtimeAttempt == retryCount) {
        return;
      }
      setState(() {
        _runtimeAttempt = retryCount;
      });
      return;
    }
    if (message.startsWith('error:')) {
      final reason = message.substring('error:'.length);
      if (_modelSourceIndex < _modelSourceCandidates.length - 1) {
        _retryModelLoad(
          advanceSource: true,
          resetAttempt: false,
          preserveTimeoutWindow: true,
        );
        return;
      }
      _setBlockingErrorMessage(_resolveLoadFailureMessage(reason));
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
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          key: ValueKey(
            'interactive_muscle_3d_viewer_${_modelSourceIndex}_$_reloadNonce',
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: false,
            useShouldOverrideUrlLoading: true,
            allowsInlineMediaPlayback: true,
            supportZoom: false,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
            isInspectable: kDebugMode,
          ),
          initialUrlRequest: URLRequest(url: WebUri('about:blank')),
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: 'ModelReady',
              callback: (arguments) {
                if (arguments.isEmpty) {
                  return null;
                }
                _handleModelReadyMessage(arguments.first.toString());
                return null;
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'TapChannel',
              callback: (arguments) {
                if (arguments.isEmpty) {
                  return null;
                }
                _handleTapMessage(arguments.first.toString());
                return null;
              },
            );
            _handleWebViewCreated(controller);
            unawaited(_loadOfflineViewerHtml(forceRebuild: true));
          },
          onLoadStop: (controller, url) {
            if (!mounted || _lifecyclePausedAt != null) {
              return;
            }
            _startModelLoadTimeoutWatchdog(preserveTimeoutWindow: true);
            _scheduleWebViewReadyProbe(resetAttempt: false);
          },
          onConsoleMessage: (_, consoleMessage) {
            if (!kDebugMode) {
              return;
            }
            debugPrint(
              '[3DViewerConsole] ${consoleMessage.messageLevel}: ${consoleMessage.message}',
            );
          },
          onReceivedError: (_, request, error) {
            if (!kDebugMode) {
              return;
            }
            debugPrint(
              '[3DViewerWebResourceError] ${request.url} code=${error.type} message=${error.description}',
            );
          },
          onReceivedHttpError: (_, request, response) {
            if (!kDebugMode) {
              return;
            }
            debugPrint(
              '[3DViewerHttpError] ${request.url} status=${response.statusCode} reason=${response.reasonPhrase}',
            );
          },
          shouldOverrideUrlLoading: (_, navigationAction) async {
            final requestUrl = navigationAction.request.url?.toString() ?? '';
            if (_isOfflineSafeRequest(requestUrl)) {
              return NavigationActionPolicy.ALLOW;
            }
            if (kDebugMode) {
              debugPrint('[3DViewerNavigationBlocked] $requestUrl');
            }
            return NavigationActionPolicy.CANCEL;
          },
        ),
        if (!_modelReady && _blockingErrorMessage == null)
          _buildLoadingOverlay(context),
        if (_blockingErrorMessage != null) _buildLoadFailureOverlay(context),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surface1.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'viewer.interactive3d.loading'.tr(),
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyMediumStyle.copyWith(
                          color: AppTheme.textHigh,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _runtimeAttempt > 0
                            ? 'viewer.interactive3d.retrying'
                                .tr(namedArgs: {'count': '$_runtimeAttempt'})
                            : 'viewer.interactive3d.optimizing'.tr(),
                        textAlign: TextAlign.center,
                        style: AppTheme.labelSmallStyle.copyWith(
                          color: AppTheme.textLow,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          _retryModelLoad(
                            advanceSource: _modelSourceIndex <
                                _modelSourceCandidates.length - 1,
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text('viewer.interactive3d.retry'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadFailureOverlay(BuildContext context) {
    final canUseNextSource =
        _modelSourceIndex < _modelSourceCandidates.length - 1;
    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.32),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surface1.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_tethering_error_rounded,
                        color: Color(0xFFFF8A80),
                        size: 30,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _blockingErrorMessage ?? _genericLoadFailureMessage,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyMediumStyle.copyWith(
                          color: AppTheme.textHigh,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        canUseNextSource
                            ? '다른 모델 소스로 전환해 다시 시도할 수 있습니다'
                            : '현재 소스에서 로딩이 실패했습니다. 네트워크 상태를 확인해주세요',
                        textAlign: TextAlign.center,
                        style: AppTheme.labelSmallStyle.copyWith(
                          color: AppTheme.textLow,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _retryModelLoad(
                          advanceSource: canUseNextSource,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text('viewer.interactive3d.retry'.tr()),
                      ),
                    ],
                  ),
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
    final direct = _ssotOrbitByCode[muscleCode];
    if (direct != null) {
      return direct;
    }
    final parent = _ssotTapOutputByDetailedCode[muscleCode];
    if (parent != null && _ssotOrbitByCode[parent] != null) {
      return _ssotOrbitByCode[parent]!;
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
    final muscleNodeMapJson = jsonEncode(_ssotSegmentedMeshNodeMap);
    final initialPayloadJson = _buildRuntimePayloadJson();
    return '''
      (() => {
        const muscleNodeMap = $muscleNodeMapJson;
        const initialPayload = $initialPayloadJson;
        const mountViewer = (viewer) => {
          if (!viewer || viewer.__musclecareMounted) {
            return;
          }
          viewer.__musclecareMounted = true;

          const runtimeState = {
            payload: initialPayload,
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
          if (!viewer) {
            return;
          }
          viewer.setAttribute('disable-zoom', '');
          viewer.setAttribute('disable-pan', '');
          viewer.setAttribute('camera-target', 'auto auto auto');
          viewer.setAttribute('min-camera-orbit', 'auto 5deg auto');
          viewer.setAttribute('max-camera-orbit', 'auto 175deg auto');
          viewer.setAttribute('orbit-sensitivity', '1.5');
          viewer.setAttribute('interpolation-decay', '20');
          viewer.setAttribute('field-of-view', 'auto');
          viewer.setAttribute('shadow-intensity', '4.4');
          viewer.setAttribute('shadow-softness', '0.8');
          viewer.setAttribute('exposure', '1.2');
          viewer.removeAttribute('environment-image');
        };

        const colors = {
          neutral: [0.10, 0.16, 0.28],
          focus: [0.55, 1.00, 0.76],
          recommend: [0.24, 0.92, 1.00],
        };

        const fatigueStops = [
          { t: 0.00, rgb: [0.00, 0.90, 0.46] }, // #00E676
          { t: 0.20, rgb: [0.78, 1.00, 0.00] }, // #C6FF00
          { t: 0.50, rgb: [1.00, 0.92, 0.00] }, // #FFEA00
          { t: 0.75, rgb: [1.00, 0.57, 0.00] }, // #FF9100
          { t: 0.90, rgb: [1.00, 0.09, 0.27] }, // #FF1744
          { t: 0.98, rgb: [0.84, 0.00, 0.00] }, // #D50000
          { t: 1.00, rgb: [0.53, 0.05, 0.31] }, // #880E4F
        ];

        const clamp01 = (value) => Math.min(Math.max(Number(value || 0), 0), 1);
        const lerp = (a, b, t) => a + ((b - a) * t);
        const lerpRgb = (a, b, t) => [
          lerp(a[0], b[0], t),
          lerp(a[1], b[1], t),
          lerp(a[2], b[2], t),
        ];
        const sampleFatigueColor = (intensity) => {
          const x = clamp01(intensity);
          for (let i = 0; i < fatigueStops.length - 1; i += 1) {
            const left = fatigueStops[i];
            const right = fatigueStops[i + 1];
            if (x >= left.t && x <= right.t) {
              const width = Math.max(right.t - left.t, 0.0001);
              const localT = clamp01((x - left.t) / width);
              return lerpRgb(left.rgb, right.rgb, localT);
            }
          }
          return fatigueStops[fatigueStops.length - 1].rgb;
        };

        const highDefinitionTargets = new Set(Object.keys(muscleNodeMap));

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

        const resolveDefinitionProfile = (muscleCode, state) => {
          const isTarget = highDefinitionTargets.has(muscleCode);
          const clampedIntensity = clamp01(state.intensity);
          if (!isTarget) {
            return {
              mixBoost: 0.0,
              roughness: 0.66,
              metallic: 0.08,
              emissiveMultiplier: state.focused ? 0.44 : state.recommended ? 0.22 : 0.0,
            };
          }
          return {
            // 매핑된 전 근육에 고선명 분리 프로파일 적용.
            mixBoost: 0.18 + (clampedIntensity * 0.14),
            roughness: 0.22 + (clampedIntensity * 0.08),
            metallic: 0.10 + (clampedIntensity * 0.08),
            emissiveMultiplier:
              (0.08 + (Math.pow(clampedIntensity, 1.15) * 0.34)) +
              (state.focused ? 0.18 : state.recommended ? 0.10 : 0.0),
          };
        };

        const applyAppearance = (material, muscleCode) => {
          try {
            if (!material || !material.pbrMetallicRoughness) {
              return;
            }
            const state = resolveMaterialState(muscleCode);
            const clampedIntensity = clamp01(state.intensity);
            const profile = resolveDefinitionProfile(muscleCode, state);
            let base = sampleFatigueColor(clampedIntensity);

            let mix =
              0.28 +
              clampedIntensity * 0.52 +
              profile.mixBoost;
            if (state.focused) {
              base = lerpRgb(base, colors.focus, 0.54);
              mix += 0.22;
            } else if (state.recommended) {
              base = lerpRgb(base, colors.recommend, 0.38);
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
            const emissive = profile.emissiveMultiplier > 0.0
              ? [
                  base[0] * profile.emissiveMultiplier,
                  base[1] * profile.emissiveMultiplier,
                  base[2] * profile.emissiveMultiplier,
                ]
              : [0.0, 0.0, 0.0];

            material.pbrMetallicRoughness.setBaseColorFactor(finalColor);
            material.pbrMetallicRoughness.setRoughnessFactor(profile.roughness);
            material.pbrMetallicRoughness.setMetallicFactor(profile.metallic);
            if (material.setEmissiveFactor) {
              material.setEmissiveFactor(emissive);
            }
          } catch (_) {}
        };

        const applyNeutralAppearance = (material) => {
          try {
            if (!material || !material.pbrMetallicRoughness) {
              return;
            }
            material.pbrMetallicRoughness.setBaseColorFactor([
              colors.neutral[0],
              colors.neutral[1],
              colors.neutral[2],
              1.0,
            ]);
            material.pbrMetallicRoughness.setRoughnessFactor(0.58);
            material.pbrMetallicRoughness.setMetallicFactor(0.12);
            if (material.setEmissiveFactor) {
              material.setEmissiveFactor([0.01, 0.01, 0.01]);
            }
          } catch (_) {}
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
            if (!material) {
              continue;
            }
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
            try {
              if (resolved) {
                applyAppearance(material, resolved);
              } else {
                applyNeutralAppearance(material);
              }
            } catch (_) {}
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

        const postToFlutter = (channel, payload) => {
          try {
            if (
              window.flutter_inappwebview &&
              typeof window.flutter_inappwebview.callHandler === 'function'
            ) {
              window.flutter_inappwebview.callHandler(channel, payload);
            }
          } catch (_) {}
        };

        let readyPosted = false;
        let errorPosted = false;
        let probeActive = false;
        const notifyReadyOnce = () => {
          if (readyPosted) {
            return;
          }
          readyPosted = true;
          probeActive = false;
          postToFlutter('ModelReady', 'ready');
        };

        const notifyErrorOnce = (code) => {
          if (readyPosted || errorPosted) {
            return;
          }
          errorPosted = true;
          probeActive = false;
          postToFlutter('ModelReady', 'error:' + code);
        };

        const stringifyError = (value) => {
          try {
            if (value == null) {
              return '';
            }
            if (typeof value === 'string') {
              return value.toLowerCase();
            }
            if (typeof value.message === 'string') {
              return String(value.message).toLowerCase();
            }
            return JSON.stringify(value).toLowerCase();
          } catch (_) {
            return '';
          }
        };

        const isOomLikeError = (text) => {
          if (!text) {
            return false;
          }
          return (
            text.includes('out of memory') ||
            text.includes('webglcontextlost') ||
            text.includes('context lost') ||
            text.includes('context_lost') ||
            text.includes('oom')
          );
        };

        const postRetryProgress = (attempt) => {
          if (attempt === 1 || attempt % 4 === 0) {
            postToFlutter('ModelReady', 'retry:' + attempt);
          }
        };

        const scheduleReadyProbe = (attempt = 0) => {
          if (attempt === 0) {
            if (probeActive) {
              return;
            }
            probeActive = true;
          }
          try {
            const applied = applyAllMaterials();
            if (applied) {
              probeActive = false;
              return;
            }
            const nextAttempt = attempt + 1;
            postRetryProgress(nextAttempt);
            if (nextAttempt < 180) {
              window.setTimeout(() => scheduleReadyProbe(nextAttempt), 180);
            } else {
              notifyErrorOnce('scene_graph_unavailable');
            }
          } catch (_) {
            const nextAttempt = attempt + 1;
            postRetryProgress(nextAttempt);
            if (nextAttempt < 180) {
              window.setTimeout(() => scheduleReadyProbe(nextAttempt), 220);
            } else {
              notifyErrorOnce('scene_graph_runtime_exception');
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

        viewer.addEventListener('error', (event) => {
          const rawDetail = event && event.detail ? event.detail : event;
          const detailText = stringifyError(rawDetail);
          if (isOomLikeError(detailText)) {
            notifyErrorOnce('model_load_failed_oom:' + detailText.slice(0, 120));
            return;
          }
          notifyErrorOnce('model_load_failed:' + detailText.slice(0, 120));
        });

        viewer.addEventListener('webglcontextlost', (event) => {
          if (event && typeof event.preventDefault === 'function') {
            event.preventDefault();
          }
          notifyErrorOnce('model_load_failed_oom');
        });

        window.addEventListener('error', (event) => {
          const text = stringifyError(
            event && event.message ? event.message : event,
          );
          if (!text) {
            return;
          }
          if (!text.includes('webgl') && !isOomLikeError(text)) {
            return;
          }
          notifyErrorOnce(isOomLikeError(text) ? 'model_load_failed_oom' : 'model_load_failed');
        });

        window.addEventListener('unhandledrejection', (event) => {
          const text = stringifyError(
            event && event.reason ? event.reason : event,
          );
          if (!text) {
            return;
          }
          if (!text.includes('webgl') && !isOomLikeError(text)) {
            return;
          }
          notifyErrorOnce(isOomLikeError(text) ? 'model_load_failed_oom' : 'model_load_failed');
        });

        viewer.addEventListener('click', (event) => {
          const muscleCode = resolveTapMuscle(event);
          if (muscleCode) {
            postToFlutter('TapChannel', muscleCode);
          }
        });

          enforceViewerConstraints();
        };

        const findViewer = () => {
          const direct =
            document.querySelector('#$_viewerId') ||
            document.querySelector('model-viewer');
          if (direct) {
            return direct;
          }
          const frames = Array.from(document.querySelectorAll('iframe'));
          for (const frame of frames) {
            try {
              const doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document);
              if (!doc) {
                continue;
              }
              const nested =
                doc.querySelector('#$_viewerId') ||
                doc.querySelector('model-viewer');
              if (nested) {
                return nested;
              }
            } catch (_) {}
          }
          return null;
        };

        const resolveViewer = (attempt = 0) => {
          const viewer = findViewer();
          if (viewer) {
            mountViewer(viewer);
            return;
          }
          if (attempt >= 80) {
            postToFlutter('ModelReady', 'error:viewer_not_found');
            return;
          }
          window.setTimeout(() => resolveViewer(attempt + 1), 120);
        };

        resolveViewer(0);
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
  final normalizedCode =
      normalizeCanonicalMuscleCode(normalized, preferDetailed: false);
  if (normalizedCode.isEmpty) {
    return null;
  }
  final aliased = _ssotAliasToCanonicalCode[normalizedCode] ?? normalizedCode;
  if (canonicalDetailedMuscleCodes.contains(aliased)) {
    return aliased;
  }
  return null;
}

const Map<String, String> _ssotAliasToCanonicalCode = {
  'pectoralis_major_clavicular': 'pectoralis_major_upper',
  'pectoralis_major_sternocostal': 'pectoralis_major_sternal',
  'pectoralis_major_abdominal': 'pectoralis_major_lower',
  'front_deltoid': 'deltoid_anterior',
  'lateral_deltoid': 'deltoid_lateral',
  'rear_deltoid': 'deltoid_posterior',
  'trapezius_descending': 'trapezius_upper',
  'trapezius_transverse': 'trapezius_middle',
  'trapezius_ascending': 'trapezius_lower',
  'biceps_brachii_long_head': 'biceps_long_head',
  'biceps_brachii_short_head': 'biceps_short_head',
  'triceps_brachii_long_head': 'triceps_long_head',
  'triceps_brachii_lateral_head': 'triceps_lateral_head',
  'triceps_brachii_medial_head': 'triceps_medial_head',
  'forearm_flexor': 'forearm_flexors',
  'forearm_extensor': 'forearm_extensors',
  'external_oblique': 'external_obliques',
  'biceps_femoris_long_head': 'biceps_femoris',
  'biceps_femoris_short_head': 'biceps_femoris',
  'gastrocnemius_medial_head': 'gastrocnemius',
  'gastrocnemius_lateral_head': 'gastrocnemius',
  'latissimus': 'latissimus_dorsi',
};

const Map<String, String> _ssotTapOutputByDetailedCode = {
  'pectoralis_major_upper': 'pectoralis_major_upper',
  'pectoralis_major_sternal': 'pectoralis_major_sternal',
  'pectoralis_major_lower': 'pectoralis_major_lower',
  'pectoralis_minor': 'pectoralis_minor',
  'deltoid_anterior': 'deltoid_anterior',
  'deltoid_lateral': 'deltoid_lateral',
  'deltoid_posterior': 'deltoid_posterior',
  'supraspinatus': 'rotator_cuff',
  'infraspinatus': 'rotator_cuff',
  'teres_minor': 'rotator_cuff',
  'subscapularis': 'rotator_cuff',
  'latissimus_dorsi': 'latissimus_dorsi',
  'trapezius_upper': 'trapezius_upper',
  'trapezius_middle': 'trapezius_middle',
  'trapezius_lower': 'trapezius_lower',
  'teres_major': 'teres_major',
  'rhomboids': 'rhomboids',
  'erector_spinae': 'erector_spinae',
  'biceps_long_head': 'biceps_long_head',
  'biceps_short_head': 'biceps_short_head',
  'brachialis': 'brachialis',
  'triceps_long_head': 'triceps_long_head',
  'triceps_lateral_head': 'triceps_lateral_head',
  'triceps_medial_head': 'triceps_medial_head',
  'forearm_flexors': 'forearm_flexors',
  'forearm_extensors': 'forearm_extensors',
  'rectus_abdominis': 'rectus_abdominis',
  'external_obliques': 'external_obliques',
  'serratus_anterior': 'serratus_anterior',
  'rectus_femoris': 'rectus_femoris',
  'vastus_lateralis': 'vastus_lateralis',
  'vastus_medialis': 'vastus_medialis',
  'gluteus_maximus': 'gluteus_maximus',
  'gluteus_medius': 'gluteus_medius',
  'biceps_femoris': 'biceps_femoris',
  'semitendinosus': 'semitendinosus',
  'gastrocnemius': 'gastrocnemius',
  'soleus': 'soleus',
  'tibialis_anterior': 'tibialis_anterior',
  'pectoralis_major_clavicular': 'pectoralis_major_upper',
  'pectoralis_major_sternocostal': 'pectoralis_major_sternal',
  'pectoralis_major_abdominal': 'pectoralis_major_lower',
  'trapezius_descending': 'trapezius_upper',
  'trapezius_transverse': 'trapezius_middle',
  'trapezius_ascending': 'trapezius_lower',
  'biceps_brachii_long_head': 'biceps_long_head',
  'biceps_brachii_short_head': 'biceps_short_head',
  'triceps_brachii_long_head': 'triceps_long_head',
  'triceps_brachii_lateral_head': 'triceps_lateral_head',
  'triceps_brachii_medial_head': 'triceps_medial_head',
  'external_oblique': 'external_obliques',
  'biceps_femoris_long_head': 'biceps_femoris',
  'biceps_femoris_short_head': 'biceps_femoris',
  'gastrocnemius_medial_head': 'gastrocnemius',
  'gastrocnemius_lateral_head': 'gastrocnemius',
};

const Map<String, String> _ssotOrbitByCode = {
  'pectoralis_major_upper': '0deg 82deg 118%',
  'pectoralis_major_sternal': '0deg 84deg 118%',
  'pectoralis_major_lower': '0deg 88deg 120%',
  'pectoralis_minor': '4deg 88deg 120%',
  'deltoid_anterior': '28deg 84deg 120%',
  'deltoid_lateral': '62deg 86deg 124%',
  'deltoid_posterior': '212deg 86deg 124%',
  'rotator_cuff': '206deg 86deg 126%',
  'latissimus_dorsi': '206deg 84deg 126%',
  'trapezius_upper': '182deg 72deg 122%',
  'trapezius_middle': '182deg 82deg 124%',
  'trapezius_lower': '182deg 92deg 126%',
  'teres_major': '204deg 88deg 126%',
  'rhomboids': '186deg 80deg 126%',
  'erector_spinae': '182deg 98deg 128%',
  'biceps_long_head': '52deg 84deg 124%',
  'biceps_short_head': '48deg 84deg 124%',
  'brachialis': '56deg 86deg 124%',
  'triceps_long_head': '232deg 84deg 126%',
  'triceps_lateral_head': '228deg 84deg 126%',
  'triceps_medial_head': '236deg 84deg 126%',
  'forearm_flexors': '66deg 92deg 132%',
  'forearm_extensors': '248deg 92deg 132%',
  'rectus_abdominis': '0deg 92deg 124%',
  'external_obliques': '24deg 90deg 126%',
  'serratus_anterior': '18deg 88deg 124%',
  'rectus_femoris': '0deg 96deg 132%',
  'vastus_lateralis': '8deg 96deg 132%',
  'vastus_medialis': '-8deg 96deg 132%',
  'gluteus_maximus': '180deg 92deg 116%',
  'gluteus_medius': '188deg 90deg 120%',
  'biceps_femoris': '184deg 98deg 134%',
  'semitendinosus': '176deg 98deg 134%',
  'gastrocnemius': '180deg 104deg 140%',
  'soleus': '180deg 106deg 142%',
  'tibialis_anterior': '0deg 102deg 140%',
};

const Map<String, List<String>> _ssotDetailedMeshSignatures = {
  'pectoralis_major_upper': [
    '05_chest',
    'material_chest',
    'clavicular_head_of_pectoralis_major_muscle',
    'pectoralis_major_clavicular',
    'chest_upper',
  ],
  'pectoralis_major_sternal': [
    '05_chest',
    'material_chest',
    'sternocostal_head_of_pectoralis_major_muscle',
    'pectoralis_major_sternocostal',
    'pectoralis_major_sternal',
    'chest_middle',
  ],
  'pectoralis_major_lower': [
    '05_chest',
    'material_chest',
    'abdominal_part_of_pectoralis_major_muscle',
    'pectoralis_major_abdominal',
    'chest_lower',
  ],
  'pectoralis_minor': ['05_chest', 'material_chest', 'pectoralis_minor_muscle'],
  'deltoid_anterior': [
    '04_shoulders',
    '10_upper_arms',
    'material_shoulders',
    'anterior_deltoid',
    'deltoid_front',
  ],
  'deltoid_lateral': [
    '04_shoulders',
    '10_upper_arms',
    'material_shoulders',
    'middle_deltoid',
    'deltoid_lateral',
  ],
  'deltoid_posterior': [
    '04_shoulders',
    '10_upper_arms',
    'material_shoulders',
    'posterior_deltoid',
    'deltoid_posterior',
  ],
  'rotator_cuff': [
    'supraspinatus_muscle',
    'infraspinatus_muscle',
    'teres_minor_muscle',
    'subscapular_muscle',
  ],
  'latissimus_dorsi': [
    '20_back',
    '21_lower_back',
    'material_lats',
    'latissimus_dorsi_muscle',
  ],
  'trapezius_upper': [
    '03_neck',
    '20_back',
    'material_neck',
    'descending_part_of_trapezius_muscle',
  ],
  'trapezius_middle': [
    '03_neck',
    '20_back',
    'material_neck',
    'transverse_part_of_trapezius_muscle',
  ],
  'trapezius_lower': [
    '03_neck',
    '20_back',
    'material_neck',
    'ascending_part_of_trapezius_muscle',
  ],
  'teres_major': ['teres_major_muscle'],
  'rhomboids': ['rhomboid_major_muscle', 'rhomboid_minor_muscle'],
  'erector_spinae': [
    '21_lower_back',
    'material_lowerback',
    'quadratus_lumborum_muscle',
    'multifidus_lumborum',
    'iliocostalis_lumborum_muscle',
    'longissimus_thoracis_muscle',
  ],
  'biceps_long_head': [
    '10_upper_arms',
    'material_upperarms',
    'biceps_brachii_long_head',
    'biceps_long_head',
  ],
  'biceps_short_head': [
    '10_upper_arms',
    'material_upperarms',
    'biceps_brachii_short_head',
    'biceps_short_head',
  ],
  'brachialis': ['10_upper_arms', 'material_upperarms', 'brachialis_muscle'],
  'triceps_long_head': [
    '10_upper_arms',
    'material_upperarms',
    'triceps_brachii_long_head',
    'triceps_long_head',
  ],
  'triceps_lateral_head': [
    '10_upper_arms',
    'material_upperarms',
    'triceps_brachii_lateral_head',
    'triceps_lateral_head',
  ],
  'triceps_medial_head': [
    '10_upper_arms',
    'material_upperarms',
    'triceps_brachii_medial_head',
    'triceps_medial_head',
  ],
  'forearm_flexors': [
    '12_fore_arms',
    'material_forearms',
    'pronator_teres_superficial',
    'flexor_carpi_radialis_muscle',
    'palmaris_longus_muscle',
  ],
  'forearm_extensors': [
    '12_fore_arms',
    'material_forearms',
    'supinator_muscle',
    'extensor_carpi_ulnaris_muscle',
    'brachioradialis_muscle',
  ],
  'rectus_abdominis': [
    '06_abdomen',
    '07_lower_abdomen',
    'material_abs',
    'rectus_abdominis_muscle',
  ],
  'external_obliques': [
    '06_abdomen',
    '07_lower_abdomen',
    'material_abs',
    'external_oblique_muscle',
  ],
  'serratus_anterior': [
    '05_chest',
    'material_chest',
    'serratus_anterior_muscle',
  ],
  'rectus_femoris': ['15_thighs', 'material_quads', 'rectus_femoris_muscle'],
  'vastus_lateralis': [
    '15_thighs',
    'material_quads',
    'vastus_lateralis_muscle',
  ],
  'vastus_medialis': ['15_thighs', 'material_quads', 'vastus_medialis_muscle'],
  'gluteus_maximus': [
    '22_buttocks',
    'material_glutes',
    'gluteus_maximus_muscle',
  ],
  'gluteus_medius': ['22_buttocks', 'material_glutes', 'gluteus_medius_muscle'],
  'biceps_femoris': [
    '15_thighs',
    'material_quads',
    'long_head_of_biceps_femoris_muscle',
    'short_head_of_biceps_femoris_muscle',
  ],
  'semitendinosus': ['15_thighs', 'material_quads', 'semitendinosus_muscle'],
  'gastrocnemius': [
    '17_legs',
    '18_ankles',
    'material_calves',
    'medial_head_of_gastrocnemius',
    'lateral_head_of_gastrocnemius',
  ],
  'soleus': ['17_legs', '18_ankles', 'material_calves', 'soleus_muscle'],
  'tibialis_anterior': ['17_legs', '16_knees', 'tibialis_anterior_muscle'],
};

final Map<String, List<String>> _ssotSegmentedMeshNodeMap =
    _buildSsotSegmentedMeshNodeMap();

Map<String, List<String>> _buildSsotSegmentedMeshNodeMap() {
  final enriched = <String, List<String>>{};
  for (final entry in _ssotDetailedMeshSignatures.entries) {
    final canonicalCode = entry.key;
    final signatures = <String>{
      canonicalCode,
      'node_$canonicalCode',
      'mesh_$canonicalCode',
      'material_$canonicalCode',
      '${canonicalCode}_muscle',
      ...entry.value,
    };
    final aliases = _ssotAliasToCanonicalCode.entries
        .where((alias) => alias.value == canonicalCode)
        .map((alias) => alias.key);
    for (final alias in aliases) {
      signatures
        ..add(alias)
        ..add('node_$alias')
        ..add('mesh_$alias')
        ..add('material_$alias');
    }
    final withSideVariants = <String>{};
    for (final signature in signatures) {
      final trimmed = signature.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      withSideVariants
        ..add(trimmed)
        ..add('left_$trimmed')
        ..add('right_$trimmed')
        ..add('l_$trimmed')
        ..add('r_$trimmed')
        ..add('${trimmed}_left')
        ..add('${trimmed}_right');
    }
    final sorted = withSideVariants.toList()..sort();
    enriched[canonicalCode] = List.unmodifiable(sorted);
  }
  return Map.unmodifiable(enriched);
}
