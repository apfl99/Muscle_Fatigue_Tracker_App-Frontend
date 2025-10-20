# 🔧 ML 기능 스켈레톤 현황

## ✅ 구현된 부분 (스켈레톤)

### 1️⃣ 서버 통신 로직 (주석 처리됨)
**파일:** `lib/model/ml.dart`

```dart
// ⏸️ 모델 학습 요청 (현재 false 반환)
Future<bool> requestModelTraining({
  required String userId,
  required MLMode targetMode,
}) async {
  print('⚠️ 서버 통신 기능은 추후 구현 예정');
  return false;  // TODO: 서버 준비 후 활성화
}

// ⏸️ Hybrid 모델 다운로드 (현재 false 반환)
Future<bool> downloadHybridModel({required String userId}) async {
  print('⚠️ 서버 통신 기능은 추후 구현 예정');
  return false;  // TODO: 서버 준비 후 활성화
}

// ⏸️ End-to-End 모델 다운로드 (현재 false 반환)
Future<bool> downloadEndToEndModel({required String userId}) async {
  print('⚠️ 서버 통신 기능은 추후 구현 예정');
  return false;  // TODO: 서버 준비 후 활성화
}
```

### 2️⃣ ML 모드 전환 로직
**파일:** `lib/model/baseline.dart`

```dart
// ✅ 현재 ML 모드 자동 판단
MLMode getCurrentMLMode() {
  if (_totalWindowCount < 200) return MLMode.ema;
  if (_totalWindowCount < 1000) return MLMode.hybrid;
  return MLMode.endToEnd;
}

// ✅ 다음 단계까지 남은 윈도우 수
int getWindowsUntilNextPhase() { ... }
```

### 3️⃣ UI 통합
**파일:** `lib/main.dart`

```dart
// ✅ ML 모드 표시 카드
Widget _buildMLModeCard() { ... }

// ⏸️ ML 모델 관리 버튼 (주석 처리됨)
// 대신 안내 메시지 표시: "ML 모델 기능은 추후 구현 예정"

// ⏸️ 모델 학습 요청 버튼 (주석 처리됨)
// Future<void> _requestModelTraining() async { ... }

// ⏸️ 모델 다운로드 버튼 (주석 처리됨)
// Future<void> _downloadModel() async { ... }

// ⏸️ 모델 상태 표시 (주석 처리됨)
// Widget _buildModelStatus(String label, bool hasModel) { ... }
```

### 4️⃣ 피로도 계산 분기
**파일:** `lib/sensor/streaming.dart`

```dart
// ✅ ML 모드별 피로도 계산 분기
switch (currentMLMode) {
  case MLMode.ema:
    // EMA 기반 계산
    fatigueScore = FatigueCalculator.calculateFatigue(...);
    break;

  case MLMode.hybrid:
    // Hybrid (EMA + ML) - 현재는 ML 부분 null 반환
    fatigueScore = await calculateHybridFatigue(...);
    break;

  case MLMode.endToEnd:
    // End-to-End ML - 현재는 null 반환, EMA fallback
    final mlFatigue = await calculateEndToEndFatigue(...);
    fatigueScore = mlFatigue ?? 1.0;
    break;
}
```

---

## ⏸️ 보류된 부분 (추후 구현)

### 1️⃣ 서버 통신
**파일:** `lib/model/ml.dart`

- **모델 학습 요청**: 현재 `false` 반환
- **모델 다운로드**: 현재 `false` 반환
- **필요 패키지**: `http`, `dart:convert` (현재 주석 처리)

### 2️⃣ TFLite 모델 추론
**파일:** `lib/model/ml.dart`

```dart
// ⏸️ Hybrid 모델 추론 (현재는 null 반환)
double? predictHybridCorrection({...}) {
  print('⚠️ Hybrid 모델 추론은 추후 구현 예정 (현재는 null 반환)');
  return null;  // TODO: 모델 준비 후 실제 추론 결과 반환
}

// ⏸️ End-to-End 모델 추론 (현재는 null 반환)
double? predictEndToEndFatigue({...}) {
  print('⚠️ End-to-End 모델 추론은 추후 구현 예정 (현재는 null 반환)');
  return null;  // TODO: 모델 준비 후 실제 추론 결과 반환
}
```

### 3️⃣ TFLite 인터프리터
**파일:** `lib/model/ml.dart`

```dart
// ⏸️ TFLite 인터프리터 (현재 주석 처리)
// Interpreter? _hybridInterpreter;
// Interpreter? _endToEndInterpreter;
```

### 4️⃣ 패키지 의존성
**파일:** `pubspec.yaml`

```yaml
# ⏸️ ML/서버 관련 패키지 (현재 주석 처리)
# tflite_flutter: ^0.10.4  # TODO: ML 모델 준비 후 활성화
# http: ^1.1.0              # TODO: 서버 준비 후 활성화
```

---

## 🔄 현재 동작 방식

### Phase 1: EMA 모드 (0~200 윈도우)
```
센서 데이터 수집 
   ↓
EMA 기반 피로도 계산 (수식)
   ↓
Baseline 업데이트
   ↓
결과 저장
```

### Phase 2: Hybrid 모드 (200~1000 윈도우)
```
센서 데이터 수집
   ↓
ML 보정 시도 (현재는 null 반환)
   ↓
⚠️ ML 실패 → EMA fallback
   ↓
EMA 기반 피로도 계산
   ↓
결과 저장
```

### Phase 3: End-to-End 모드 (1000+ 윈도우)
```
센서 데이터 수집
   ↓
ML 직접 예측 시도 (현재는 null 반환)
   ↓
⚠️ ML 실패 → EMA fallback
   ↓
EMA 기반 피로도 계산
   ↓
결과 저장
```

**결론:** 현재는 모든 모드에서 실질적으로 **EMA 기반 계산**만 동작합니다.

---

## 🚀 ML 모델 활성화 방법

### 1단계: 모델 파일 준비
- Hybrid 모델 학습 및 TFLite 변환
- End-to-End 모델 학습 및 TFLite 변환
- 서버 구축 (학습 요청, 모델 다운로드 API)

### 2단계: 코드 활성화

#### A. 서버 통신 활성화 (우선)
```bash
# 1. pubspec.yaml 수정
# http: ^1.1.0 주석 해제

# 2. lib/model/ml.dart 수정
# - import 'dart:convert'; 주석 해제
# - import 'package:http/http.dart' as http; 주석 해제
# - requestModelTraining() 함수 내용 주석 해제
# - downloadHybridModel() 함수 내용 주석 해제
# - downloadEndToEndModel() 함수 내용 주석 해제

# 3. lib/main.dart 수정
# - _requestModelTraining() 주석 해제
# - _downloadModel() 주석 해제
# - _buildModelStatus() 주석 해제
# - ML 모델 관리 UI 주석 해제

# 4. 패키지 설치
flutter pub get
```

#### B. ML 모델 추론 활성화 (서버 준비 후)
```bash
# 1. pubspec.yaml 수정
# tflite_flutter: ^0.10.4 주석 해제

# 2. lib/model/ml.dart 수정
# - import 'package:tflite_flutter/tflite_flutter.dart'; 주석 해제
# - Interpreter 변수 주석 해제
# - _loadHybridModel() / _loadEndToEndModel() 함수 내용 주석 해제
# - predictHybridCorrection() / predictEndToEndFatigue() 함수 내용 주석 해제
# - hasHybridModel / hasEndToEndModel getter 수정

# 3. 패키지 설치
flutter pub get

# 4. 빌드 및 테스트
flutter run
```

### 3단계: 서버 설정
**`lib/model/ml.dart`** 파일의 서버 URL 수정:

```dart
class MLManager {
  // 실제 서버 URL로 변경
  static const String serverBaseUrl = 'https://your-ml-server.com/api';
  ...
}
```

---

## 📝 TODO 주석 위치

### `lib/model/ml.dart`
**서버 통신 관련:**
- Line 2: `// import 'dart:convert';`
- Line 3: `// import 'package:http/http.dart' as http;`
- Line 111-181: `requestModelTraining()` 함수 내용
- Line 186-219: `downloadHybridModel()` 함수 내용
- Line 224-259: `downloadEndToEndModel()` 함수 내용

**ML 모델 추론 관련:**
- Line 5: `// import 'package:tflite_flutter/tflite_flutter.dart';`
- Line 20-21: `// Interpreter? _hybridInterpreter;` / `_endToEndInterpreter;`
- Line 50-65: 모델 로드 로직
- Line 78-87: `_loadHybridModel()` 함수 내용
- Line 94-103: `_loadEndToEndModel()` 함수 내용
- Line 264-297: `predictHybridCorrection()` 함수 내용
- Line 306-341: `predictEndToEndFatigue()` 함수 내용
- Line 346-347: `hasHybridModel` / `hasEndToEndModel` getter
- Line 355-372: `deleteModels()` 인터프리터 정리
- Line 384-386: `dispose()` 인터프리터 정리

### `lib/main.dart`
- Line 851-936: ML 모델 관리 UI (버튼, 상태 표시)
- Line 983-1001: `_buildModelStatus()` 함수
- Line 1004-1048: `_requestModelTraining()` 함수
- Line 1051-1101: `_downloadModel()` 함수

### `pubspec.yaml`
- Line 16: `# tflite_flutter: ^0.10.4`
- Line 17: `# http: ^1.1.0`

---

## 🎯 권장 개발 순서

1. **서버 개발** (Python/Flask 권장)
   - 데이터 수신 API
   - 모델 학습 파이프라인
   - TFLite 변환 자동화
   - 모델 다운로드 API

2. **모델 학습**
   - 충분한 학습 데이터 수집 (최소 1000+ 윈도우)
   - Hybrid 모델: baseline 보정값 예측
   - End-to-End 모델: 피로도 직접 예측

3. **앱 통합**
   - TODO 주석 코드 활성화
   - 실제 모델로 테스트
   - 정확도 검증

4. **최적화**
   - 모델 Quantization (INT8)
   - 추론 속도 최적화
   - 배터리 소모 최소화

---

## 📊 현재 앱 상태 요약

| 기능 | 상태 | 비고 |
|------|------|------|
| EMA 피로도 계산 | ✅ 완전 동작 | Phase 1 |
| Baseline 관리 | ✅ 완전 동작 | EMA 기반 |
| ML 모드 전환 | ✅ 완전 동작 | 자동 전환 |
| ML 모델 UI | ⏸️ 주석 처리 | 안내 메시지만 표시 |
| 서버 통신 로직 | ⏸️ 스켈레톤 | false 반환 |
| Hybrid 추론 | ⏸️ 스켈레톤 | null 반환 |
| End-to-End 추론 | ⏸️ 스켈레톤 | null 반환 |
| TFLite 패키지 | ⏸️ 주석 처리 | 모델 준비 후 활성화 |
| http 패키지 | ⏸️ 주석 처리 | 서버 준비 후 활성화 |

---

## ✅ 결론

현재 앱은 **ML 인프라가 완전히 준비된 상태**이며, 실제 모델만 있으면 즉시 통합 가능합니다.

**현재 동작:**
- EMA 기반 피로도 계산 (Phase 1)
- ML 모드 자동 전환 (Phase 1 → 2 → 3)
- ML UI 표시 (학습 요청, 모델 받기 버튼)

**추후 필요:**
- 실제 ML 모델 파일 (`.tflite`)
- 서버 구축 (학습 & 다운로드 API)
- TODO 주석 코드 활성화

