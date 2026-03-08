import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'database_helper.dart';
import 'measure_session.dart';

class HybridFatiguePayload {
  HybridFatiguePayload({
    required this.rmsAcc,
    required this.rmsGyro,
    required this.meanFreqAcc,
    required this.meanFreqGyro,
    required this.rmsBase,
    required this.freqBase,
    required this.userEmbedding,
  });

  final double rmsAcc;
  final double rmsGyro;
  final double meanFreqAcc;
  final double meanFreqGyro;
  final double rmsBase;
  final double freqBase;
  final List<double> userEmbedding;

  Map<String, dynamic> toJson() {
    final sanitizedEmb = List<double>.from(userEmbedding);
    const targetLength = 12;
    if (sanitizedEmb.length < targetLength) {
      sanitizedEmb
          .addAll(List<double>.filled(targetLength - sanitizedEmb.length, 0.0));
    } else if (sanitizedEmb.length > targetLength) {
      sanitizedEmb.removeRange(targetLength, sanitizedEmb.length);
    }

    return {
      'rms_acc': rmsAcc,
      'rms_gyro': rmsGyro,
      'mean_freq_acc': meanFreqAcc,
      'mean_freq_gyro': meanFreqGyro,
      'rms_base': rmsBase,
      'freq_base': freqBase,
      'user_emb': sanitizedEmb,
    };
  }
}

class HybridFatigueResponse {
  HybridFatigueResponse({
    required this.fatigue,
    this.modelVersion,
    required this.latencyMs,
  });

  final double fatigue;
  final String? modelVersion;
  final int latencyMs;
}

/// ========================================
/// ML 모델 관리자 (싱글톤)
/// - 서버 통신 (모델 학습 요청, 다운로드)
/// - 온디바이스 모델 추론 (Hybrid, End-to-End)
/// ========================================
class MLManager {
  static final MLManager instance = MLManager._internal();
  factory MLManager() => instance;
  MLManager._internal();

  // TFLite 인터프리터
  Interpreter? _hybridInterpreter;
  Interpreter? _endToEndInterpreter;
  String? _loadedE2EModelPath;
  String? _loadedE2EVersion;
  List<List<int>>? _e2eInputShapes;
  List<TensorType>? _e2eInputTypes;
  List<int>? _e2eOutputShape;
  _E2EMetadata? _e2eMetadata;

  // 서버 설정 (개발자가 실제 서버 URL로 변경 필요)
  static const String serverBaseUrl = 'https://your-ml-server.com/api';
  static const String hybridPredictUrl =
      'https://merry99-musclecare-train-hybrid.hf.space/predict';
  static const Duration _aiLatencyMask = Duration(milliseconds: 320);
  static const String trainEndpoint = '/model/train';
  static const String downloadHybridEndpoint = '/model/hybrid/download';
  static const String downloadEndToEndEndpoint = '/model/endtoend/download';

  // 로컬 모델 파일 경로
  String? _hybridModelPath;
  String? _endToEndModelPath;

  // 초기화 상태
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// ========================================
  /// 초기화: 로컬 모델 파일 확인 및 로드
  /// ========================================
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🤖 ML Manager 초기화 시작...');

      final appDir = await getApplicationDocumentsDirectory();
      _hybridModelPath = '${appDir.path}/hybrid_model.tflite';
      _endToEndModelPath = '${appDir.path}/endtoend_model.tflite';

      await _loadEndToEndModelFromDb();
      if (_endToEndInterpreter == null && _endToEndModelPath != null) {
        await _loadLegacyEndToEndModel(_endToEndModelPath!);
      }

      _isInitialized = true;
      print(
        '✅ ML Manager 초기화 완료 (E2E 모델: '
        '${_endToEndInterpreter != null ? 'loaded' : 'not loaded'})',
      );
    } catch (e, stackTrace) {
      print('❌ ML Manager 초기화 오류: $e');
      print(stackTrace);
    }
  }

  Future<void> _loadEndToEndModelFromDb({bool force = false}) async {
    try {
      final info = await DatabaseHelper.instance.getModelVersion('E2E');
      final modelPath = info?['path'] as String?;
      final version = info?['version'] as String?;

      if (modelPath == null || modelPath.isEmpty) {
        print('⚠️ E2E 모델 경로 정보가 없습니다 (DB).');
        return;
      }

      final file = File(modelPath);
      if (!await file.exists()) {
        print('⚠️ E2E 모델 파일을 찾을 수 없습니다: $modelPath');
        return;
      }

      if (!force &&
          _endToEndInterpreter != null &&
          _loadedE2EModelPath == modelPath) {
        print('ℹ️ E2E 모델이 이미 로드되어 있습니다 (version: $_loadedE2EVersion)');
        return;
      }

      await _loadEndToEndModel(file, version: version);
    } catch (e, stackTrace) {
      print('❌ E2E 모델 로드(DB) 실패: $e');
      print(stackTrace);
    }
  }

  Future<void> _loadLegacyEndToEndModel(String modelPath) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        return;
      }
      await _loadEndToEndModel(file);
    } catch (e, stackTrace) {
      print('❌ 레거시 E2E 모델 로드 실패: $e');
      print(stackTrace);
    }
  }

  Future<void> _loadEndToEndModel(
    File file, {
    String? version,
  }) async {
    try {
      final options = InterpreterOptions();
      if (Platform.isAndroid || Platform.isIOS) {
        options.threads = 2;
      }
      _endToEndInterpreter?.close();
      _endToEndInterpreter = Interpreter.fromFile(file, options: options);
      try {
        await _loadE2EMetadata(modelFile: file);
        final metadata = _e2eMetadata;
        if (metadata != null) {
          _endToEndInterpreter?.resizeInputTensor(
            0,
            [1, metadata.inputDim],
          );
        }
        _endToEndInterpreter?.allocateTensors();
      } catch (e, stackTrace) {
        print('⚠️ E2E allocateTensors 실패: $e');
        print(stackTrace);
      }
      final inputTensors = _endToEndInterpreter!.getInputTensors();
      final inputCount = inputTensors.length;
      _e2eInputShapes = inputTensors
          .map((tensor) => List<int>.from(tensor.shape))
          .toList(growable: false);
      _e2eInputTypes =
          inputTensors.map((tensor) => tensor.type).toList(growable: false);
      final outputTensor = _endToEndInterpreter!.getOutputTensor(0);
      _e2eOutputShape = List<int>.from(outputTensor.shape);
      _loadedE2EModelPath = file.path;
      _loadedE2EVersion = version;
      print(
        '✅ End-to-End 모델 로드 성공: ${file.path} '
        '(version: ${version ?? 'unknown'})',
      );
      for (var i = 0; i < inputCount; i++) {
        print(
          'ℹ️ E2E 입력[$i] → shape=${_e2eInputShapes![i]} '
          'type=${_e2eInputTypes![i]}',
        );
      }
      print(
        'ℹ️ E2E 출력 텐서 → shape=$_e2eOutputShape type=${outputTensor.type}',
      );
    } catch (e, stackTrace) {
      print('❌ End-to-End 모델 로드 실패: $e');
      print(stackTrace);
      _endToEndInterpreter = null;
    }
  }

  Future<void> reloadEndToEndModel() async {
    if (!_isInitialized) {
      await initialize();
      return;
    }
    await _loadEndToEndModelFromDb(force: true);
  }

  /// ========================================
  /// Hybrid/AI 예측 API 호출 (서버 사이드 모델)
  /// ========================================
  Future<HybridFatigueResponse?> requestHybridFatigue({
    required HybridFatiguePayload payload,
    required MLMode mode,
  }) async {
    final uri = Uri.parse(hybridPredictUrl);
    final stopwatch = Stopwatch()..start();
    http.Response? response;
    try {
      print('🌐 Hybrid API 요청 시작 → mode=${mode.name}');
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload.toJson()),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        print('❌ Hybrid API 실패 (status=${response.statusCode})');
        return null;
      }

      var body = response.body.trim();
      if (body.endsWith('%')) {
        body = body.substring(0, body.length - 1).trim();
      }
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        print('❌ Hybrid API JSON 파싱 실패: $e, body: $body');
        return null;
      }

      final fatigueRaw = decoded['fatigue'];
      if (fatigueRaw is! num) {
        print('❌ Hybrid API 응답에 fatigue 값이 없습니다: $body');
        return null;
      }

      final fatigue = fatigueRaw.toDouble();
      final safeFatigue =
          fatigue.isFinite ? fatigue.clamp(1.0, 3.0).toDouble() : 1.0;
      final version = decoded['model_version']?.toString();
      final latency = stopwatch.elapsedMilliseconds;

      print(
        '🤖 Hybrid API 결과 → fatigue=${safeFatigue.toStringAsFixed(3)}, '
        'version=$version, latency=${latency}ms',
      );

      return HybridFatigueResponse(
        fatigue: safeFatigue,
        modelVersion: version,
        latencyMs: latency,
      );
    } catch (e, stackTrace) {
      print('❌ Hybrid API 호출 실패: $e');
      print(stackTrace);
      return null;
    } finally {
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final maskMs =
          _aiLatencyMask.inMilliseconds.clamp(0, double.infinity).toInt();
      if (elapsed < maskMs) {
        await Future.delayed(Duration(milliseconds: maskMs - elapsed));
      }
    }
  }

  Future<HybridFatigueResponse?> predictHybridFatigue({
    required double rmsAcc,
    required double meanFreqAcc,
    required double rmsGyro,
    required double meanFreqGyro,
    required double rmsBase,
    required double freqBase,
    required List<double> userEmbedding,
    MLMode mode = MLMode.hybrid,
  }) async {
    final payload = HybridFatiguePayload(
      rmsAcc: rmsAcc,
      rmsGyro: rmsGyro,
      meanFreqAcc: meanFreqAcc,
      meanFreqGyro: meanFreqGyro,
      rmsBase: rmsBase,
      freqBase: freqBase,
      userEmbedding: userEmbedding,
    );
    return await requestHybridFatigue(
      payload: payload,
      mode: mode,
    );
  }

  /// ========================================
  /// ========================================
  /// Hybrid 모드: ML 기반 baseline 보정값 예측
  /// 입력: [rms, freq, prevFatigue]
  /// 출력: baseline 보정값 (adjRMS_base)
  /// ========================================
  Future<double?> predictHybridCorrection({
    required double rms,
    required double freq,
    required double prevFatigue,
  }) async {
    try {
      // 서버 API를 통한 보정값 예측
      final payload = HybridFatiguePayload(
        rmsAcc: rms,
        rmsGyro: 0.0, // Hybrid 모드에서는 RMS만 사용
        meanFreqAcc: freq,
        meanFreqGyro: 0.0, // Hybrid 모드에서는 Freq만 사용
        rmsBase: 0.0,
        freqBase: 0.0,
        userEmbedding:
            List<double>.filled(12, prevFatigue), // 12개 embedding으로 확장
      );

      final response = await requestHybridFatigue(
        payload: payload,
        mode: MLMode.hybrid,
      );

      if (response != null) {
        // 서버에서 반환된 컨디션 값을 보정값으로 사용
        final correction = response.fatigue;
        print('🤖 Hybrid 보정값 예측 (서버): $correction');
        return correction;
      }

      print('⚠️ Hybrid 서버 API 실패, null 반환');
      return null;
    } catch (e) {
      print('❌ Hybrid 보정값 예측 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// End-to-End 모드: ML이 직접 컨디션 예측
  /// ========================================
  static const List<String> _defaultFeatureColumns = [
    'rms_acc',
    'rms_gyro',
    'mean_freq_acc',
    'mean_freq_gyro',
    'entropy_acc',
    'entropy_gyro',
    'jerk_mean',
    'jerk_std',
    'stability_index',
    'fatigue_prev',
  ];

  Future<double?> predictEndToEndFatigue({
    required Map<String, dynamic> window,
  }) async {
    final qualityFlag = window['quality_flag'];
    if (qualityFlag is num && qualityFlag.toInt() == 0) {
      print('⚠️ 품질 미달 윈도우 → E2E 추론 생략');
      return null;
    }
    final lowMotionFlag = window['low_motion_flag'];
    if (lowMotionFlag is num && lowMotionFlag.toInt() == 1) {
      print('ℹ️ 저활동 윈도우 → E2E 추론 생략');
      return null;
    }

    final interpreter = _endToEndInterpreter;
    final metadata = _e2eMetadata;
    if (interpreter == null) {
      print('⚠️ End-to-End 모델이 로드되지 않았습니다. EMA로 대체합니다.');
      return null;
    }
    if (metadata == null) {
      print('⚠️ E2E 메타데이터가 없어 EMA로 대체합니다.');
      return null;
    }

    try {
      final normalized = _normalizeFeatures(window, metadata);
      final embedding =
          _extractEmbedding(window['user_emb'], metadata.embeddingDim);

      final inputVector = Float32List.fromList([
        ...normalized,
        ...embedding,
      ]);

      final outputBuffer = List<List<double>>.generate(
        1,
        (_) => List<double>.filled(1, 0.0),
        growable: false,
      );

      print(
        '🧠 E2E 추론 정보 → inputDim=${metadata.inputDim}, '
        'features=${metadata.featureColumns.length}, embedding=${metadata.embeddingDim}',
      );

      interpreter.run([inputVector], outputBuffer);

      final prediction = outputBuffer[0][0];
      if (prediction.isNaN) {
        print('⚠️ End-to-End 모델 결과가 NaN입니다.');
        return null;
      }

      final fatigue = prediction.clamp(1.0, 3.0).toDouble();
      print(
        '🤖 End-to-End 컨디션 예측: ${fatigue.toStringAsFixed(3)} '
        '(version: ${_loadedE2EVersion ?? 'unknown'})',
      );
      return fatigue;
    } catch (e, stackTrace) {
      print('❌ End-to-End 추론 오류: $e');
      print(stackTrace);
      return null;
    }
  }

  List<double> _normalizeFeatures(
    Map<String, dynamic> window,
    _E2EMetadata metadata,
  ) {
    final normalized = List<double>.filled(metadata.featureColumns.length, 0.0);
    for (var i = 0; i < metadata.featureColumns.length; i++) {
      final key = metadata.featureColumns[i];
      final rawValue = window[key];
      double value;
      if (rawValue is num) {
        value = rawValue.toDouble();
      } else if (rawValue is String) {
        value = double.tryParse(rawValue) ?? 0.0;
      } else {
        value = 0.0;
      }
      final scale =
          metadata.scalerScale[i].abs() < 1e-9 ? 1.0 : metadata.scalerScale[i];
      normalized[i] = (value - metadata.scalerMean[i]) / scale;
    }
    return normalized;
  }

  List<double> _extractEmbedding(
    dynamic raw,
    int targetDim,
  ) {
    List<double> values;
    if (raw is Uint8List) {
      values = raw.map((e) => e.toDouble()).toList();
    } else if (raw is String) {
      try {
        final list = (jsonDecode(raw) as List).cast<num>();
        values = list.map((e) => e.toDouble()).toList();
      } catch (_) {
        values = const [];
      }
    } else if (raw is List) {
      values = raw.whereType<num>().map((e) => e.toDouble()).toList();
    } else {
      values = const [];
    }

    final embedding = List<double>.filled(targetDim, 0.0);
    final length = min(values.length, targetDim);
    for (var i = 0; i < length; i++) {
      embedding[i] = values[i];
    }
    return embedding;
  }

  Future<void> _loadE2EMetadata({required File modelFile}) async {
    try {
      final dir = modelFile.parent;
      final metadataFile =
          File(p.join(dir.path, 'cnn_gru_fatigue_metadata.json'));
      if (!await metadataFile.exists()) {
        print('⚠️ E2E 메타데이터가 없어 기본 설정을 사용합니다');
        _e2eMetadata = _E2EMetadata.defaultColumns(_defaultFeatureColumns, 12);
        return;
      }

      final json =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      _e2eMetadata =
          _E2EMetadata.fromJson(json, defaultColumns: _defaultFeatureColumns);
      print(
        'ℹ️ E2E 메타데이터 로드 완료 → '
        'features=${_e2eMetadata!.featureColumns.length}, '
        'embedding=${_e2eMetadata!.embeddingDim}, '
        'inputDim=${_e2eMetadata!.inputDim}',
      );
    } catch (e, stackTrace) {
      print('⚠️ E2E 메타데이터 로드 실패: $e');
      print(stackTrace);
      _e2eMetadata = _E2EMetadata.defaultColumns(_defaultFeatureColumns, 12);
    }
  }

  /// ========================================
  /// 모델 상태 확인 (TODO: 모델 준비 후 실제 상태 반환)
  /// ========================================
  bool get hasHybridModel => _hybridInterpreter != null;
  bool get hasEndToEndModel => _endToEndInterpreter != null;

  /// ========================================
  /// 모델 삭제 (재학습 시)
  /// ========================================
  Future<void> deleteModels() async {
    try {
      _hybridInterpreter?.close();
      _hybridInterpreter = null;
      _endToEndInterpreter?.close();
      _endToEndInterpreter = null;
      _loadedE2EModelPath = null;
      _loadedE2EVersion = null;

      if (_hybridModelPath != null && await File(_hybridModelPath!).exists()) {
        await File(_hybridModelPath!).delete();
        print('🗑️ Hybrid 모델 삭제 완료');
      }

      if (_endToEndModelPath != null &&
          await File(_endToEndModelPath!).exists()) {
        await File(_endToEndModelPath!).delete();
        print('🗑️ End-to-End 모델 삭제 완료');
      }

      print('⚠️ 모델 삭제 완료 (인터프리터 초기화)');
    } catch (e) {
      print('❌ 모델 삭제 오류: $e');
    }
  }

  /// ========================================
  /// 리소스 정리 (TODO: 모델 준비 후 활성화)
  /// ========================================
  void dispose() {
    _hybridInterpreter?.close();
    _hybridInterpreter = null;
    _endToEndInterpreter?.close();
    _endToEndInterpreter = null;
    _isInitialized = false;
    print('🧹 ML Manager 리소스 정리 완료');
  }
}

/// ========================================
/// Hybrid 컨디션 계산 (EMA + ML 결합)
/// ========================================
Future<double> calculateHybridFatigue({
  required double rms,
  required double freq,
  required double rmsBase,
  required double freqBase,
  required double prevFatigue,
}) async {
  // ML 보정값 가져오기
  final mlCorrection = await MLManager.instance.predictHybridCorrection(
    rms: rms,
    freq: freq,
    prevFatigue: prevFatigue,
  );

  // ML 모델이 없거나 오류 시 EMA만 사용
  if (mlCorrection == null) {
    print('⚠️ ML 보정 실패, EMA만 사용');
    return FatigueCalculator.calculateFatigue(
      rms: rms,
      peakFreq: freq,
      rmsBase: rmsBase,
      freqBase: freqBase,
    );
  }

  // Hybrid 계산: EMA 70% + ML 30%
  final adjRmsBase = MLPhaseConstants.emaWeight * rmsBase +
      MLPhaseConstants.mlWeight * mlCorrection;

  // 컨디션 계산
  final fatigue = FatigueCalculator.calculateFatigue(
    rms: rms,
    peakFreq: freq,
    rmsBase: adjRmsBase,
    freqBase: freqBase,
  );

  print('🔀 Hybrid 컨디션 계산:');
  print('   - EMA RMS_base: $rmsBase');
  print('   - ML 보정값: $mlCorrection');
  print('   - 조정 RMS_base: $adjRmsBase');
  print('   - 최종 Fatigue: $fatigue');

  return fatigue;
}

/// ========================================
/// End-to-End 컨디션 계산 (ML 직접 예측)
/// ========================================
Future<double?> calculateEndToEndFatigue({
  required Map<String, dynamic> window,
  required double rms,
  required double freq,
  required double rmsBase,
  required double freqBase,
}) async {
  final mlPrediction = await MLManager.instance.predictEndToEndFatigue(
    window: window,
  );

  final fallback = FatigueCalculator.calculateFatigue(
    rms: rms,
    peakFreq: freq,
    rmsBase: rmsBase,
    freqBase: freqBase,
  );

  if (mlPrediction == null) {
    print('⚠️ End-to-End 예측 실패, EMA 결과 사용');
    return fallback;
  }

  final blended = (mlPrediction * 0.8) + (fallback * 0.2);
  final result = blended.clamp(1.0, 3.0);
  print(
    '🎯 End-to-End 컨디션 최종값: ${result.toStringAsFixed(3)} '
    '(ML=${mlPrediction.toStringAsFixed(3)}, EMA=${fallback.toStringAsFixed(3)})',
  );
  return result;
}

class _E2EMetadata {
  final List<String> featureColumns;
  final List<double> scalerMean;
  final List<double> scalerScale;
  final int embeddingDim;

  const _E2EMetadata({
    required this.featureColumns,
    required this.scalerMean,
    required this.scalerScale,
    required this.embeddingDim,
  });

  int get inputDim => featureColumns.length + embeddingDim;

  factory _E2EMetadata.fromJson(
    Map<String, dynamic> json, {
    required List<String> defaultColumns,
  }) {
    final featureColumns =
        (json['feature_columns'] as List?)?.whereType<String>().toList() ??
            List<String>.from(defaultColumns);

    final scaler = json['scaler'] as Map<String, dynamic>? ?? const {};
    final meanList = (scaler['mean'] as List?)
            ?.whereType<num>()
            .map((e) => e.toDouble())
            .toList() ??
        List<double>.filled(featureColumns.length, 0.0);
    final scaleList = (scaler['scale'] as List?)
            ?.whereType<num>()
            .map((e) => e.toDouble())
            .toList() ??
        List<double>.filled(featureColumns.length, 1.0);

    _ensureLength(meanList, featureColumns.length, fill: 0.0);
    _ensureLength(scaleList, featureColumns.length, fill: 1.0);

    final embeddingDim = (json['embedding_dim'] as num?)?.toInt() ?? 12;

    return _E2EMetadata(
      featureColumns: featureColumns,
      scalerMean: meanList,
      scalerScale: scaleList,
      embeddingDim: embeddingDim,
    );
  }

  factory _E2EMetadata.defaultColumns(
    List<String> columns,
    int embeddingDim,
  ) {
    return _E2EMetadata(
      featureColumns: List<String>.from(columns),
      scalerMean: List<double>.filled(columns.length, 0.0),
      scalerScale: List<double>.filled(columns.length, 1.0),
      embeddingDim: embeddingDim,
    );
  }

  static void _ensureLength(
    List<double> list,
    int length, {
    required double fill,
  }) {
    if (list.length >= length) {
      list.removeRange(length, list.length);
    } else {
      list.addAll(List<double>.filled(length - list.length, fill));
    }
  }
}
