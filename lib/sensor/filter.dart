import 'dart:math';
import 'dart:io' show Platform;

/// ---------------------------------------------------------------------------
/// Adaptive Motion Filter
/// - iOS / Android 모두 사용 가능
/// - 실시간 샘플링 주파수(fs) 자동 추정
/// - 플랫폼별 cutoff 자동 보정 (Android는 약간 낮게)
/// - 중력 제거 + Band-pass (1~15Hz 기준)
/// ---------------------------------------------------------------------------
class MotionFilterAdaptive {
  // 내부 IIR 필터들
  final _gx = _IIR1(); // 중력 추정용 (x)
  final _gy = _IIR1(); // 중력 추정용 (y)
  final _gz = _IIR1(); // 중력 추정용 (z)
  final _hp = _IIR1(); // Band-pass HP (1Hz)
  final _lp = _IIR1(); // Band-pass LP (15Hz)

  // 샘플링 주파수 추정 관련
  double _prevTime = 0.0;
  double _fs = 50.0; // 초기값 (Hz)
  double _dt = 0.02; // 초기값 (초)

  /// 센서 입력 1회마다 호출
  /// ax, ay, az: raw accelerometer (m/s²)
  /// now: microsecondsSinceEpoch (현재 시각)
  double process(double ax, double ay, double az, int now) {
    // ① 실시간 샘플링 주기 계산
    if (_prevTime != 0) {
      final delta = (now - _prevTime) / 1e6; // 초 단위
      if (delta > 0.002 && delta < 0.1) {
        // 10~500Hz 사이만 허용
        _dt = delta;
        _fs = 1.0 / _dt;
      }
    }
    _prevTime = now.toDouble();

    // ② 플랫폼별 cutoff 보정
    final isAndroid = Platform.isAndroid;
    final gravityFc = isAndroid ? 0.3 : 0.4; // 중력 LPF
    final hpFc = isAndroid ? 0.8 : 1.0; // Band-pass 하단
    final lpFc = isAndroid ? 12.0 : 15.0; // Band-pass 상단

    // ③ 중력 제거 (LPF)
    final gx = _gx.lpf(ax, _dt, gravityFc);
    final gy = _gy.lpf(ay, _dt, gravityFc);
    final gz = _gz.lpf(az, _dt, gravityFc);

    final lx = ax - gx;
    final ly = ay - gy;
    final lz = az - gz;

    // ④ magnitude 계산
    final mag = sqrt(lx * lx + ly * ly + lz * lz);

    // ⑤ Band-pass(HP → LP)
    final hp = _hp.hpf(mag, _dt, hpFc);
    final bp = _lp.lpf(hp, _dt, lpFc);

    return bp;
  }

  double get fs => _fs; // 현재 추정된 샘플링 주파수
  double get dt => _dt;

  /// 필터 리셋
  void reset() {
    _gx.reset();
    _gy.reset();
    _gz.reset();
    _hp.reset();
    _lp.reset();
    _prevTime = 0.0;
    _fs = 50.0;
    _dt = 0.02;
  }
}

/// ---------------------------------------------------------------------------
/// 1차 IIR 필터 클래스 (LPF / HPF 공용)
/// ---------------------------------------------------------------------------
class _IIR1 {
  double _prevY = 0.0;
  double _prevX = 0.0;

  double lpf(double x, double dt, double fc) {
    final tau = 1.0 / (2 * pi * fc);
    final alpha = dt / (tau + dt);
    _prevY = _prevY + alpha * (x - _prevY);
    _prevX = x;
    return _prevY;
  }

  double hpf(double x, double dt, double fc) {
    final tau = 1.0 / (2 * pi * fc);
    final alpha = tau / (tau + dt);
    final y = alpha * (_prevY + x - _prevX);
    _prevY = y;
    _prevX = x;
    return y;
  }

  void reset() {
    _prevY = 0.0;
    _prevX = 0.0;
  }
}
