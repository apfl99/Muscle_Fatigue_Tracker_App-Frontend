import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';

class PersonalWeights {
  PersonalWeights({
    required this.denseWeights,
    required this.denseBias,
    required this.lastUpdate,
    required this.dataPoints,
  });

  final List<List<double>> denseWeights;
  final List<double> denseBias;
  final DateTime lastUpdate;
  final int dataPoints;

  Map<String, dynamic> toJson() => {
        'dense_weights': denseWeights,
        'dense_bias': denseBias,
        'last_update': lastUpdate.toIso8601String(),
        'data_points': dataPoints,
      };

  static PersonalWeights fromJson(Map<String, dynamic> json) {
    final denseWeights = (json['dense_weights'] as List<dynamic>? ?? [])
        .map(
          (row) => (row as List<dynamic>)
              .map((value) => (value as num).toDouble())
              .toList(),
        )
        .toList();
    final denseBias = (json['dense_bias'] as List<dynamic>? ?? [])
        .map((value) => (value as num).toDouble())
        .toList();
    final lastUpdate = DateTime.parse(json['last_update'] as String);
    final dataPoints = (json['data_points'] as num?)?.toInt() ?? 0;

    return PersonalWeights(
      denseWeights: denseWeights,
      denseBias: denseBias,
      lastUpdate: lastUpdate,
      dataPoints: dataPoints,
    );
  }
}

class PersonalWeightsStorage {
  static const String _fileName = 'user_weights.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<PersonalWeights?> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final jsonMap = jsonDecode(await file.readAsString());
      return PersonalWeights.fromJson(jsonMap as Map<String, dynamic>);
    } catch (e) {
      appLog('❌ 개인화 weight 로드 실패: $e');
      return null;
    }
  }

  static Future<void> save(PersonalWeights weights) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(weights.toJson()), flush: true);
      appLog('💾 개인화 weight 저장 완료: ${file.path}');
    } catch (e) {
      appLog('❌ 개인화 weight 저장 실패: $e');
    }
  }
}
