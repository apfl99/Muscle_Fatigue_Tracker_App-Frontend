import 'dart:math';

import 'personal_weights.dart';

class PersonalTrainer {
  PersonalTrainer._();

  static const _featureKeys = [
    'rms_acc',
    'mean_freq_acc',
    'rms_gyro',
    'mean_freq_gyro',
    'fatigue',
  ];

  static const _regularization = 1e-3;
  static const _pivotEpsilon = 1e-9;

  static Future<PersonalWeights> train({
    required List<Map<String, dynamic>> windows,
    required int dataPoints,
  }) async {
    if (windows.isEmpty) {
      throw ArgumentError('train() requires non empty windows');
    }

    final samples = <List<double>>[];
    final targets = <double>[];

    for (final window in windows) {
      final target = (window['fatigue'] as num?)?.toDouble();
      if (target == null || target.isNaN) continue;

      final featureVector = <double>[];
      var hasValid = false;
      for (final key in _featureKeys) {
        final value = (window[key] as num?)?.toDouble() ?? 0.0;
        if (!value.isNaN) hasValid = true;
        featureVector.add(value.isNaN ? 0.0 : value);
      }
      if (!hasValid) continue;
      featureVector.add(1.0); // bias term

      samples.add(featureVector);
      targets.add(target);
    }

    if (samples.length < 2) {
      final fallback = _buildFallbackWeights(targets);
      return fallback;
    }

    final featureCount = _featureKeys.length + 1; // +1 for bias
    final xtx = List.generate(
      featureCount,
      (_) => List<double>.filled(featureCount, 0.0),
    );
    final xty = List<double>.filled(featureCount, 0.0);

    for (var idx = 0; idx < samples.length; idx++) {
      final x = samples[idx];
      final y = targets[idx];
      for (var i = 0; i < featureCount; i++) {
        xty[i] += x[i] * y;
        for (var j = 0; j < featureCount; j++) {
          xtx[i][j] += x[i] * x[j];
        }
      }
    }

    for (var i = 0; i < featureCount; i++) {
      xtx[i][i] += _regularization;
    }

    final solution = _solveLinearSystem(xtx, xty);
    if (solution == null) {
      final fallback = _buildFallbackWeights(targets);
      return fallback;
    }

    final weights = solution.take(_featureKeys.length).toList();
    final bias = solution.last;

    final clippedWeights =
        weights.map((w) => w.clamp(-0.2, 0.2).toDouble()).toList();
    final clippedBias = bias.clamp(1.0, 2.5).toDouble();

    return PersonalWeights(
      denseWeights: [clippedWeights],
      denseBias: [clippedBias],
      lastUpdate: DateTime.now().toUtc(),
      dataPoints: dataPoints,
    );
  }

  static PersonalWeights _buildFallbackWeights(List<double> targets) {
    final bias = targets.isEmpty ? 1.0 : _mean(targets);
    return PersonalWeights(
      denseWeights: [
        List<double>.filled(_featureKeys.length, 0.0),
      ],
      denseBias: [bias.clamp(1.0, 2.5).toDouble()],
      lastUpdate: DateTime.now().toUtc(),
      dataPoints: targets.length,
    );
  }

  static List<double>? _solveLinearSystem(
    List<List<double>> a,
    List<double> b,
  ) {
    final n = b.length;
    final augmented = List.generate(
      n,
      (i) => List<double>.from(a[i])..add(b[i]),
    );

    for (var i = 0; i < n; i++) {
      var pivot = i;
      var maxVal = augmented[i][i].abs();
      for (var r = i + 1; r < n; r++) {
        final val = augmented[r][i].abs();
        if (val > maxVal) {
          maxVal = val;
          pivot = r;
        }
      }

      if (maxVal < _pivotEpsilon) {
        return null;
      }

      if (pivot != i) {
        final temp = augmented[i];
        augmented[i] = augmented[pivot];
        augmented[pivot] = temp;
      }

      final pivotValue = augmented[i][i];
      for (var c = i; c <= n; c++) {
        augmented[i][c] /= pivotValue;
      }

      for (var r = 0; r < n; r++) {
        if (r == i) continue;
        final factor = augmented[r][i];
        for (var c = i; c <= n; c++) {
          augmented[r][c] -= factor * augmented[i][c];
        }
      }
    }

    return List<double>.generate(n, (i) => augmented[i][n]);
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.fold<double>(0.0, (a, b) => a + b);
    return sum / max(values.length, 1);
  }
}
