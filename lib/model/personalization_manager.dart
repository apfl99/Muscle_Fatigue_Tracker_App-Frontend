import 'dart:math';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';

import 'database_helper.dart';
import 'model_downloader.dart';
import 'personal_trainer.dart';
import 'personal_weights.dart';

class PersonalizationManager {
  PersonalizationManager._();

  static final PersonalizationManager instance = PersonalizationManager._();

  static const int _activationThreshold = 10;
  static const int _retentionDays = 7;
  static const Duration _minTrainingInterval = Duration(hours: 12);
  static const double _blendFactor = 0.35;
  static const double _maxPersonalDelta = 0.4;
  static const List<String> _featureKeys = [
    'rms_acc',
    'mean_freq_acc',
    'rms_gyro',
    'mean_freq_gyro',
    'fatigue',
  ];

  PersonalWeights? _cachedWeights;
  DateTime? _lastTrainingTime;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    appLog('🤖 PersonalizationManager 초기화 시작');
    try {
      await ModelDownloader.instance.downloadLatest();
    } catch (error, stackTrace) {
      appLog('⚠️ Personalization 모델 다운로드 건너뜀: $error');
      appLog(stackTrace);
    }
    _cachedWeights = await PersonalWeightsStorage.load();
    _lastTrainingTime = _cachedWeights?.lastUpdate;
    _initialized = true;
    appLog('✅ PersonalizationManager 초기화 완료');
  }

  Future<void> ensurePersonalization({bool force = false}) async {
    final count = await DatabaseHelper.instance.getValidWindowCount();
    appLog('📊 개인화 데이터 개수: $count');

    if (count < _activationThreshold) {
      appLog(
        'ℹ️ 개인화 활성화 조건 미충족 '
        '($count/$_activationThreshold) → global 모델 유지',
      );
      if (_cachedWeights != null) {
        appLog('ℹ️ 개인화 weight 비활성화 (데이터 부족)');
      }
      _cachedWeights = null;
      return;
    }

    final now = DateTime.now().toUtc();
    if (!force &&
        _lastTrainingTime != null &&
        now.difference(_lastTrainingTime!) < _minTrainingInterval) {
      appLog('⏳ 최근 학습됨 → 다음 학습까지 대기 (${_lastTrainingTime!.toLocal()})');
      return;
    }

    final windows = await DatabaseHelper.instance.getRecentWindows(
      days: _retentionDays,
      limit: max(count, 500),
    );
    if (windows.isEmpty) {
      appLog('⚠️ 학습할 윈도우 데이터가 없습니다');
      return;
    }

    final weights = await PersonalTrainer.train(
      windows: windows,
      dataPoints: count,
    );
    await PersonalWeightsStorage.save(weights);
    _cachedWeights = weights;
    _lastTrainingTime = weights.lastUpdate;

    appLog(
      '✅ 개인화 weight 업데이트 완료 '
      '(데이터 $count개, lastUpdate=${weights.lastUpdate.toLocal()})',
    );
  }

  PersonalWeights? get currentWeights => _cachedWeights;

  bool get isPersonalizationActive =>
      _cachedWeights != null &&
      _cachedWeights!.dataPoints >= _activationThreshold;

  double applyPersonalization({
    required Map<String, double> features,
    required double fallback,
  }) {
    if (!isPersonalizationActive) return fallback;
    final weights = _cachedWeights!;
    if (weights.denseWeights.isEmpty) return fallback;

    final row = weights.denseWeights.first;
    final bias = weights.denseBias.isNotEmpty ? weights.denseBias.first : null;

    final hasOutlierWeight = row.any((w) => w.abs() > 0.5);
    final biasOutOfRange =
        bias == null || bias.isNaN || bias < 0.9 || bias > 2.6;
    if (hasOutlierWeight || biasOutOfRange) {
      appLog(
        '⚠️ 개인화 weight가 허용 범위를 벗어났습니다. '
        '(outlierWeight=$hasOutlierWeight, bias=$bias) → fallback 사용',
      );
      return fallback;
    }

    double prediction = 0.0;
    for (int i = 0; i < _featureKeys.length && i < row.length; i++) {
      final value = features[_featureKeys[i]] ?? 0.0;
      prediction += row[i] * value;
    }
    prediction += bias;

    final double cappedPrediction = prediction.clamp(
      fallback - _maxPersonalDelta,
      fallback + _maxPersonalDelta,
    );

    if (!identical(prediction, cappedPrediction)) {
      appLog(
        'ℹ️ 개인화 prediction 조정: raw=${prediction.toStringAsFixed(3)} '
        '→ capped=${cappedPrediction.toStringAsFixed(3)} '
        '(fallback=${fallback.toStringAsFixed(3)})',
      );
    }

    final blended =
        fallback * (1.0 - _blendFactor) + cappedPrediction * _blendFactor;
    final double clamped = blended.clamp(1.0, 3.0).toDouble();
    appLog(
      '🎯 개인화 적용: base=${fallback.toStringAsFixed(3)} '
      '→ personal=${clamped.toStringAsFixed(3)} '
      '(prediction=${prediction.toStringAsFixed(3)})',
    );
    return clamped;
  }
}
