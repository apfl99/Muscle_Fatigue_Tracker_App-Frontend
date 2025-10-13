import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';

/// 센서 데이터 수집 서비스
class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  double? _lastAccX, _lastAccY, _lastAccZ;
  double? _lastGyroX, _lastGyroY, _lastGyroZ;

  final _sensorDataController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;

  /// 센서 데이터 수집 시작 (100Hz 목표)
  void startListening() {
    // 가속도계 데이터 수집
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        _lastAccX = event.x;
        _lastAccY = event.y;
        _lastAccZ = event.z;
        _emitSensorData();
      },
    );

    // 자이로스코프 데이터 수집
    _gyroscopeSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        _lastGyroX = event.x;
        _lastGyroY = event.y;
        _lastGyroZ = event.z;
        _emitSensorData();
      },
    );
  }

  void _emitSensorData() {
    if (_lastAccX != null &&
        _lastAccY != null &&
        _lastAccZ != null &&
        _lastGyroX != null &&
        _lastGyroY != null &&
        _lastGyroZ != null) {
      _sensorDataController.add(
        SensorData(
          timestamp: DateTime.now(),
          accelerometerX: _lastAccX!,
          accelerometerY: _lastAccY!,
          accelerometerZ: _lastAccZ!,
          gyroscopeX: _lastGyroX!,
          gyroscopeY: _lastGyroY!,
          gyroscopeZ: _lastGyroZ!,
        ),
      );
    }
  }

  /// 센서 데이터 수집 중지
  void stopListening() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
  }

  void dispose() {
    stopListening();
    _sensorDataController.close();
  }
}

