# Hybrid 모델 측정 결과 미표시 문제 원인 분석

## 문제 현상
Hybrid 모드에서 측정 결과가 가끔 안 보이는 문제

## 원인 분석

### 1. Hybrid API 실패 시 결과 전달 누락

**위치**: `lib/sensor/streaming.dart` 943-963줄

```dart
// UI에 결과 전달
if (_lastWindowResult != null) {
  final sessionAvgResult = Map<String, dynamic>.from(_lastWindowResult!);
  sessionAvgResult['fatigueScore'] = avgFatigue;
  // ... 결과 전달
  onAnalysisResult?.call(sessionAvgResult);
}
```

**문제점**:
- `_lastWindowResult`가 null이면 결과가 전달되지 않음
- Hybrid API가 실패해도 EMA 기반 `avgFatigue`는 계산되지만, `_lastWindowResult`가 없으면 결과가 전달되지 않음

### 2. Hybrid API 실패 시 `_lastWindowResult` 업데이트 누락

**위치**: `lib/sensor/streaming.dart` 835-860줄

```dart
if (aiResponse != null) {
  avgFatigue = aiResponse.fatigue;
  // ...
  _lastWindowResult?['fatigueScore'] = avgFatigue;  // 848줄: aiResponse가 있을 때만 실행
} else {
  _lastHybridResponse = null;
  // aiResponse가 null이면 _lastWindowResult['fatigueScore']가 업데이트되지 않음
}
```

**문제점**:
- Hybrid API가 실패하면 (`aiResponse == null`), `_lastWindowResult['fatigueScore']`가 업데이트되지 않음
- 하지만 `avgFatigue`는 EMA 기반으로 계산된 값이 있음 (798-803줄)
- 결과 전달 시 `sessionAvgResult['fatigueScore'] = avgFatigue`로 덮어쓰지만, `_lastWindowResult`가 null이면 결과 자체가 전달되지 않음

### 3. 네트워크 타임아웃 및 오류 처리

**위치**: `lib/model/ml.dart` 250-308줄

```dart
response = await http.post(...).timeout(const Duration(seconds: 3));

if (response.statusCode != 200) {
  return null;  // 실패 시 null 반환
}
```

**문제점**:
- 네트워크 타임아웃(3초) 또는 서버 오류 시 null 반환
- 이 경우에도 EMA 기반 결과는 있지만, Hybrid API 실패로 인해 결과가 표시되지 않을 수 있음

### 4. 프리페치 실패 시 처리

**위치**: `lib/sensor/streaming.dart` 807-818줄, 821-832줄

```dart
if (aiResponse == null && _inFlightHybridRequest != null) {
  // 프리페치 대기 중 오류 발생 시 aiResponse는 여전히 null
  aiResponse = await _inFlightHybridRequest;
}

if (aiResponse == null) {
  // 원격 추론 실패 시에도 aiResponse는 null
  aiResponse = await _performHybridRequest();
}
```

**문제점**:
- 프리페치나 원격 추론이 모두 실패하면 `aiResponse`가 null
- 이 경우 EMA 기반 결과가 있어도 표시되지 않을 수 있음

## 해결 방안

### 방안 1: Hybrid API 실패 시에도 EMA 결과 표시 (권장)

`lib/sensor/streaming.dart` 858-860줄 수정:

```dart
} else {
  _lastHybridResponse = null;
  // Hybrid API 실패 시에도 EMA 기반 avgFatigue를 사용하여 결과 표시
  if (_lastWindowResult != null) {
    _lastWindowResult!['fatigueScore'] = avgFatigue;
  }
}
```

### 방안 2: `_lastWindowResult`가 null일 때도 결과 전달

`lib/sensor/streaming.dart` 942-963줄 수정:

```dart
// UI에 결과 전달
if (_lastWindowResult != null) {
  // 기존 로직
} else if (currentMLMode == model_config.MLMode.hybrid && avgFatigue > 0) {
  // Hybrid 모드에서 _lastWindowResult가 null이어도 avgFatigue가 있으면 결과 전달
  final sessionAvgResult = {
    'fatigueScore': avgFatigue,
    'fatigueRMS': avgRms,
    'fatigueVariance': _currentSessionWindows
        .map((w) => w['variance'] as double)
        .reduce((a, b) => a + b) / _currentSessionWindows.length,
    'peakFreq': avgFreq,
    'fatiguePeakFreq': avgFreq,
    'fatigueLevel': FatigueCalculator.getFatigueLevel(avgFatigue),
    'mlMode': currentMLMode.name,
    'qualityWarning': false,
  };
  onAnalysisResult?.call(sessionAvgResult);
}
```

### 방안 3: Hybrid API 재시도 로직 추가

네트워크 오류 시 자동 재시도 또는 폴백 로직 추가

## 권장 수정 사항

1. **즉시 수정**: 방안 1 적용 - Hybrid API 실패 시에도 EMA 결과 표시
2. **추가 개선**: 방안 2 적용 - `_lastWindowResult`가 null일 때도 결과 전달
3. **장기 개선**: 네트워크 오류 시 재시도 로직 및 사용자 알림 추가

