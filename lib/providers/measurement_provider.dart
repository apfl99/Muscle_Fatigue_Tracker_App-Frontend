import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/fatigue_result.dart';
import '../models/user_baseline.dart';
import '../services/sensor_service.dart';
import '../services/analysis_service.dart';
import '../services/local_storage_service.dart';

enum MeasurementState {
  idle,
  measuring,
  analyzing,
  completed,
  error,
}

/// 측정 화면 상태관리 Provider
class MeasurementProvider extends ChangeNotifier {
  final SensorService _sensorService;
  final AnalysisService _analysisService;
  final LocalStorageService _storageService;

  MeasurementProvider({
    required SensorService sensorService,
    required AnalysisService analysisService,
    required LocalStorageService storageService,
  })  : _sensorService = sensorService,
        _analysisService = analysisService,
        _storageService = storageService;

  MeasurementState _state = MeasurementState.idle;
  MeasurementState get state => _state;

  final List<SensorData> _sensorDataBuffer = [];
  List<SensorData> get sensorDataBuffer => List.unmodifiable(_sensorDataBuffer);

  FatigueResult? _latestResult;
  FatigueResult? get latestResult => _latestResult;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  double _progress = 0.0;
  double get progress => _progress;

  StreamSubscription<SensorData>? _sensorSubscription;
  Timer? _measurementTimer;

  static const int measurementDurationSeconds = 5;
  static const int targetSampleCount = 500; // 100Hz * 5초

  /// 측정 시작
  Future<void> startMeasurement({String? userId}) async {
    try {
      _state = MeasurementState.measuring;
      _sensorDataBuffer.clear();
      _progress = 0.0;
      _errorMessage = null;
      notifyListeners();

      // 센서 수집 시작
      _sensorService.startListening();
      _sensorSubscription = _sensorService.sensorDataStream.listen(
        (data) {
          _sensorDataBuffer.add(data);
          _progress = (_sensorDataBuffer.length / targetSampleCount).clamp(0.0, 1.0);
          notifyListeners();
        },
      );

      // 5초 후 자동 종료
      _measurementTimer = Timer(
        const Duration(seconds: measurementDurationSeconds),
        () => _finishMeasurement(userId: userId),
      );
    } catch (e) {
      _state = MeasurementState.error;
      _errorMessage = '측정 시작 오류: $e';
      notifyListeners();
    }
  }

  /// 측정 종료 및 분석
  Future<void> _finishMeasurement({String? userId}) async {
    _measurementTimer?.cancel();
    _sensorSubscription?.cancel();
    _sensorService.stopListening();

    if (_sensorDataBuffer.length < 100) {
      _state = MeasurementState.error;
      _errorMessage = '센서 데이터가 충분하지 않습니다.';
      notifyListeners();
      return;
    }

    try {
      _state = MeasurementState.analyzing;
      notifyListeners();

      // Baseline 불러오기 또는 초기화
      UserBaseline? baseline = await _storageService.loadBaseline();
      baseline ??= UserBaseline.initial(userId ?? 'guest');

      // 피로도 분석
      _latestResult = await _analysisService.analyzeFatigue(
        sensorData: _sensorDataBuffer,
        baseline: baseline,
        userId: userId,
      );

      // Baseline 업데이트
      final updatedBaseline = baseline.updateWith(
        newRms: _latestResult!.rms,
        newVariance: _latestResult!.variance,
        newFrequency: _latestResult!.dominantFrequency,
      );
      await _storageService.saveBaseline(updatedBaseline);

      // 결과 로컬 저장
      await _storageService.saveFatigueResult(_latestResult!);

      _state = MeasurementState.completed;
      notifyListeners();
    } catch (e) {
      _state = MeasurementState.error;
      _errorMessage = '분석 오류: $e';
      notifyListeners();
    }
  }

  /// 측정 취소
  void cancelMeasurement() {
    _measurementTimer?.cancel();
    _sensorSubscription?.cancel();
    _sensorService.stopListening();
    _sensorDataBuffer.clear();
    _state = MeasurementState.idle;
    _progress = 0.0;
    notifyListeners();
  }

  /// 상태 초기화
  void reset() {
    cancelMeasurement();
    _latestResult = null;
    _errorMessage = null;
  }

  @override
  void dispose() {
    cancelMeasurement();
    super.dispose();
  }
}

