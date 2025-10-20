# 🤖 ML 기능 사용 가이드

## ⚠️ 현재 상태

**현재 버전은 ML 기능의 스켈레톤(프레임워크)만 구현되어 있습니다.**

- ⏸️ **서버 통신 로직** (주석 처리됨, `false` 반환)
- ✅ ML 모드 전환 로직 (EMA → Hybrid → End-to-End)
- ⏸️ **UI 표시** (ML 모델 관리 버튼 주석 처리, 안내 메시지만 표시)
- ⏸️ **ML 모델 추론** (주석 처리됨, `null` 반환)

실제 서버와 TFLite 모델이 준비되면 `lib/model/ml.dart`와 `lib/main.dart`의 `// TODO` 주석을 따라 코드를 활성화하면 됩니다.

---

## 📋 개요

근피로도 측정 앱은 **3단계 ML 도입 전략**을 따릅니다:

1. **Phase 1: EMA 개인화** (0~200 윈도우)
2. **Phase 2: Hybrid 보정** (200~1000 윈도우)
3. **Phase 3: End-to-End ML** (1000+ 윈도우)

---

## 🚀 구현된 기능

### 1️⃣ 자동 ML 모드 전환

- 측정 횟수에 따라 자동으로 ML 모드가 전환됩니다.
- 각 측정마다 baseline이 업데이트되고, 총 윈도우 수가 증가합니다.
- UI에서 현재 모드와 다음 단계까지의 진행률을 확인할 수 있습니다.

### 2️⃣ 서버 통신

#### **모델 학습 요청**
```dart
// 사용자 ID와 타겟 모드를 서버에 전송
final success = await MLManager.instance.requestModelTraining(
  userId: 'user_test_001',
  targetMode: MLMode.hybrid, // 또는 MLMode.endToEnd
);
```

**서버 엔드포인트:**
- `POST /api/model/train`
- **요청 바디:**
```json
{
  "user_id": "user_test_001",
  "target_mode": "hybrid",
  "data_count": 1000,
  "training_data": [
    {
      "timestamp": "2025-10-19T10:30:00Z",
      "rms": 0.1234,
      "variance": 0.0567,
      "peak_freq": 12.5,
      "mean_power_freq": 10.3,
      "median_freq": 11.2,
      "fatigue": 1.25,
      "sample_count": 250,
      "sampling_rate": 50.0
    },
    ...
  ]
}
```

#### **모델 다운로드**
```dart
// Hybrid 모델 다운로드
final success = await MLManager.instance.downloadHybridModel(
  userId: 'user_test_001',
);

// End-to-End 모델 다운로드
final success = await MLManager.instance.downloadEndToEndModel(
  userId: 'user_test_001',
);
```

**서버 엔드포인트:**
- `GET /api/model/hybrid/download?user_id=user_test_001`
- `GET /api/model/endtoend/download?user_id=user_test_001`
- **응답:** TFLite 모델 파일 (`.tflite`)

### 3️⃣ 온디바이스 추론

#### **Hybrid 모드**
```dart
// EMA 70% + ML 보정 30%
final fatigue = await calculateHybridFatigue(
  rms: 0.1234,
  freq: 12.5,
  rmsBase: 0.1000,
  freqBase: 15.0,
  prevFatigue: 1.2,
);
```

**ML 모델 입력:**
- `[rms, freq, prevFatigue]` (정규화된 값)

**ML 모델 출력:**
- baseline 보정값

#### **End-to-End 모드**
```dart
// ML이 직접 피로도 예측
final fatigue = await calculateEndToEndFatigue(
  windowData: filteredData, // 5초 윈도우 센서 데이터
  rms: 0.1234,
  freq: 12.5,
  rmsBase: 0.1000,
  freqBase: 15.0,
);
```

**ML 모델 입력:**
- 5초 윈도우 센서 데이터 (약 250 샘플)
- 형태: `[1, 250, 1]` (batch, timesteps, features)

**ML 모델 출력:**
- 피로도 점수 (1.0~2.0)

---

## 🛠️ 서버 구현 요구사항

### 1️⃣ 모델 학습 엔드포인트

**`POST /api/model/train`**

```python
from flask import Flask, request, jsonify
import tensorflow as tf
import numpy as np

app = Flask(__name__)

@app.route('/api/model/train', methods=['POST'])
def train_model():
    data = request.json
    user_id = data['user_id']
    target_mode = data['target_mode']
    training_data = data['training_data']
    
    # 데이터 전처리
    X, y = preprocess_training_data(training_data, target_mode)
    
    # 모델 학습
    if target_mode == 'hybrid':
        model = train_hybrid_model(X, y)
        save_path = f'models/{user_id}_hybrid.tflite'
    else:  # endToEnd
        model = train_endtoend_model(X, y)
        save_path = f'models/{user_id}_endtoend.tflite'
    
    # TFLite 변환 및 저장
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    with open(save_path, 'wb') as f:
        f.write(tflite_model)
    
    return jsonify({
        'message': '모델 학습 완료',
        'training_id': f'{user_id}_{target_mode}_{datetime.now().timestamp()}'
    })
```

### 2️⃣ 모델 다운로드 엔드포인트

**`GET /api/model/hybrid/download`**

```python
@app.route('/api/model/hybrid/download', methods=['GET'])
def download_hybrid_model():
    user_id = request.args.get('user_id')
    model_path = f'models/{user_id}_hybrid.tflite'
    
    if not os.path.exists(model_path):
        return jsonify({'error': '모델을 찾을 수 없습니다'}), 404
    
    return send_file(model_path, mimetype='application/octet-stream')
```

**`GET /api/model/endtoend/download`**

```python
@app.route('/api/model/endtoend/download', methods=['GET'])
def download_endtoend_model():
    user_id = request.args.get('user_id')
    model_path = f'models/{user_id}_endtoend.tflite'
    
    if not os.path.exists(model_path):
        return jsonify({'error': '모델을 찾을 수 없습니다'}), 404
    
    return send_file(model_path, mimetype='application/octet-stream')
```

---

## 📱 앱 사용 흐름

### 1️⃣ 초기 사용 (Phase 1: EMA)

1. 앱 실행 후 "데이터 수집" 버튼 클릭
2. 5초간 센서 데이터 수집
3. EMA 기반 피로도 계산 및 baseline 업데이트
4. 결과 저장 (SQLite)

### 2️⃣ Hybrid 전환 (200+ 윈도우)

1. 자동으로 Hybrid 모드로 전환
2. "ML 모델 관리" 섹션 표시
3. **"학습 요청"** 버튼 클릭 → 서버에 데이터 전송
4. 서버에서 학습 완료 후 **"모델 받기"** 버튼 클릭
5. Hybrid 모델 다운로드 및 자동 로드
6. 이후 측정부터 Hybrid 보정 적용

### 3️⃣ End-to-End 전환 (1000+ 윈도우)

1. 자동으로 End-to-End 모드로 전환
2. **"학습 요청"** → **"모델 받기"** 과정 반복
3. End-to-End 모델로 직접 피로도 예측

---

## 🔧 설정 변경

### 서버 URL 변경

**`lib/model/ml.dart`** 파일의 `MLManager` 클래스:

```dart
class MLManager {
  // 서버 설정 (개발자가 실제 서버 URL로 변경)
  static const String serverBaseUrl = 'https://your-ml-server.com/api';
  static const String trainEndpoint = '/model/train';
  static const String downloadHybridEndpoint = '/model/hybrid/download';
  static const String downloadEndToEndEndpoint = '/model/endtoend/download';
  ...
}
```

### 사용자 ID 변경

**`lib/main.dart`** 파일의 `_requestModelTraining`, `_downloadModel` 함수:

```dart
// 사용자 ID (실제로는 인증된 사용자 ID 사용)
const userId = 'user_test_001'; // ← 여기를 변경
```

### ML 전환 임계값 변경

**`lib/model/config.dart`** 파일의 `MLPhaseConstants`:

```dart
class MLPhaseConstants {
  static const int emaPhaseThreshold = 200;      // 1단계 → 2단계
  static const int hybridPhaseThreshold = 300;   // 2단계 → 3단계 (테스트용으로 낮춤)
  static const int endToEndPhaseThreshold = 1000; // 최종 단계
  ...
}
```

---

## 🧪 테스트 시나리오

### 시나리오 1: EMA 모드 (초기)

1. 앱 실행
2. 5~10회 측정
3. baseline이 안정화되는지 확인

### 시나리오 2: Hybrid 전환

1. 300회 측정 (또는 임계값 변경)
2. "학습 요청" 클릭
3. 서버 로그 확인 (데이터 수신 확인)
4. "모델 받기" 클릭
5. 모델 다운로드 및 로드 확인
6. 다음 측정에서 Hybrid 로그 확인

### 시나리오 3: End-to-End 전환

1. 1000회 측정
2. 위 과정 반복
3. End-to-End 예측 로그 확인

---

## 📊 로그 확인

앱 실행 시 다음 로그를 통해 ML 상태를 확인할 수 있습니다:

```
🤖 ML Manager 초기화 시작...
✅ Hybrid 모델 로드 성공: /path/to/hybrid_model.tflite
✅ End-to-End 모델 로드 성공: /path/to/endtoend_model.tflite
✅ ML Manager 초기화 완료

...

📊 현재 Baseline:
   - RMS Base: 0.1234
   - Freq Base: 15.00 Hz
   - ML Mode: Hybrid 보정

🟡 Phase 2: Hybrid 보정 모드
🤖 Hybrid 보정값 예측: 0.1050
🔀 Hybrid 피로도 계산:
   - EMA RMS_base: 0.1000
   - ML 보정값: 0.1050
   - 조정 RMS_base: 0.1015
   - 최종 Fatigue: 1.28
```

---

## ⚠️ 주의사항

1. **서버 구현 필수**: ML 기능을 사용하려면 위 엔드포인트를 구현한 서버가 필요합니다.
2. **네트워크 권한**: 앱이 서버와 통신할 수 있도록 네트워크 권한이 필요합니다.
3. **TFLite 모델 형식**: 서버에서 반드시 TFLite 형식으로 모델을 변환하여 제공해야 합니다.
4. **모델 크기**: 온디바이스 추론을 위해 모델 크기를 최소화해야 합니다 (< 5MB 권장).
5. **Fallback 로직**: ML 모델이 없거나 오류 발생 시 자동으로 EMA 모드로 복귀합니다.

---

## 🔗 관련 파일

- **ML 로직**: `lib/model/ml.dart`
- **센서 처리**: `lib/sensor/streaming.dart`
- **UI 표시**: `lib/main.dart` (`_buildMLModeCard` 함수)
- **설정**: `lib/model/config.dart`
- **Baseline 관리**: `lib/model/baseline.dart`

---

## 📦 필요 패키지

```yaml
dependencies:
  # tflite_flutter: ^0.10.4  # TODO: ML 모델 준비 후 활성화
  # http: ^1.1.0              # TODO: 서버 준비 후 활성화
  path_provider: ^2.1.1       # 로컬 파일 저장
```

**서버 및 모델 준비 후:**
1. `pubspec.yaml`에서 `http`, `tflite_flutter` 주석 해제
2. `lib/model/ml.dart`와 `lib/main.dart`에서 `// TODO` 주석 코드 활성화
3. `flutter pub get` 실행

---

## 🎯 다음 단계

1. ✅ ML 프레임워크 구현 완료 (스켈레톤)
2. ⏳ **ML 모델 학습 및 TFLite 변환** (가장 중요)
3. ⏳ `lib/model/ml.dart`의 TODO 코드 활성화
4. ⏳ 서버 구현 (Python/Flask 또는 Node.js)
5. ⏳ 모델 최적화 (Quantization, Pruning)
6. ⏳ 온디바이스 재학습 (선택사항)

### 🔧 서버 및 ML 모델 활성화 체크리스트

#### A. 서버 통신 활성화 (우선)
- [ ] 서버 구축 (Python/Flask 등)
  - [ ] `POST /api/model/train` 엔드포인트
  - [ ] `GET /api/model/hybrid/download` 엔드포인트
  - [ ] `GET /api/model/endtoend/download` 엔드포인트
- [ ] `pubspec.yaml`에서 `http` 패키지 주석 해제
- [ ] `lib/model/ml.dart`에서 다음 주석 해제:
  - [ ] `import 'dart:convert';`
  - [ ] `import 'package:http/http.dart' as http;`
  - [ ] `requestModelTraining()` 함수 내용
  - [ ] `downloadHybridModel()` / `downloadEndToEndModel()` 함수 내용
- [ ] `lib/main.dart`에서 다음 주석 해제:
  - [ ] `_requestModelTraining()` 함수
  - [ ] `_downloadModel()` 함수
  - [ ] `_buildModelStatus()` 함수
  - [ ] ML 모델 관리 UI 섹션
- [ ] `flutter pub get` 실행
- [ ] 서버 URL 설정 (`lib/model/ml.dart`)

#### B. ML 모델 추론 활성화 (서버 준비 후)
- [ ] TensorFlow/PyTorch로 Hybrid/End-to-End 모델 학습
- [ ] 모델을 TFLite 형식으로 변환 (`.tflite`)
- [ ] `pubspec.yaml`에서 `tflite_flutter` 패키지 주석 해제
- [ ] `lib/model/ml.dart`에서 다음 주석 해제:
  - [ ] `import 'package:tflite_flutter/tflite_flutter.dart';`
  - [ ] `Interpreter? _hybridInterpreter;` / `_endToEndInterpreter;`
  - [ ] `_loadHybridModel()` / `_loadEndToEndModel()` 함수 내용
  - [ ] `predictHybridCorrection()` / `predictEndToEndFatigue()` 함수 내용
  - [ ] `hasHybridModel` / `hasEndToEndModel` getter 내용
- [ ] `flutter pub get` 실행
- [ ] 앱 빌드 및 테스트

---

## 💡 팁

- 테스트를 위해 `hybridPhaseThreshold`를 `50`으로 낮추면 빠르게 Hybrid 모드를 체험할 수 있습니다.
- 서버가 없는 경우, 더미 모델 파일(`.tflite`)을 직접 앱 번들에 포함시켜 테스트할 수 있습니다.
- 실제 사용 환경에서는 사용자 인증(JWT 등)을 추가해야 합니다.

