/// 센서 데이터 모델
class SensorData {
  final DateTime timestamp;
  final double accelerometerX;
  final double accelerometerY;
  final double accelerometerZ;
  final double gyroscopeX;
  final double gyroscopeY;
  final double gyroscopeZ;

  SensorData({
    required this.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'accelerometerX': accelerometerX,
        'accelerometerY': accelerometerY,
        'accelerometerZ': accelerometerZ,
        'gyroscopeX': gyroscopeX,
        'gyroscopeY': gyroscopeY,
        'gyroscopeZ': gyroscopeZ,
      };

  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
        timestamp: DateTime.parse(json['timestamp'] as String),
        accelerometerX: (json['accelerometerX'] as num).toDouble(),
        accelerometerY: (json['accelerometerY'] as num).toDouble(),
        accelerometerZ: (json['accelerometerZ'] as num).toDouble(),
        gyroscopeX: (json['gyroscopeX'] as num).toDouble(),
        gyroscopeY: (json['gyroscopeY'] as num).toDouble(),
        gyroscopeZ: (json['gyroscopeZ'] as num).toDouble(),
      );
}

