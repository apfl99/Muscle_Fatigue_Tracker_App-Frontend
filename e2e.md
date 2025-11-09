## `/model` API

모델 다운로드 엔드포인트는 최신 모델과 특정 버전의 모델을 모두 제공하며, 응답 헤더를 통해 실제 버전 정보를 확인할 수 있습니다.

### 요청 형식

```
GET /model
GET /model?version={번호}
GET /model?version={번호}&filename={파일명}
```

| 파라미터 | 타입 | 설명 |
| --- | --- | --- |
| `version` (선택) | int | 생략하거나 빈 값이면 최신 모델. 지정하면 해당 버전 확인 후 다운로드. |
| `filename` (선택) | string | 내려받을 파일명. 기본값은 환경 변수 `HF_E2E_MODEL_FILE` (기본 `cnn_gru_fatigue.tflite`). |

### 응답

- 본문: 요청한 모델 바이너리 (예: `.tflite`, `.keras`, 메타데이터 등)
- 헤더:
  - `X-Model-Version`: 실제 다운로드된 모델 버전
  - `X-Model-Filename`: 반환된 파일명
- 에러:
  - `404` – 요청한 버전이 현재 `model_version`보다 크거나 manifest에 존재하지 않을 때
  - `500` – Hugging Face Hub 다운로드 실패 등 내부 오류

### 동작 규칙

1. 서버는 `training_state.json`의 `model_version` 값을 읽어 현재 허용 가능한 최대 버전을 확인합니다.
2. `version`을 지정하지 않으면 최신 모델(현재 버전)을 다운로드합니다.
3. `version`을 지정하면 서버가 현재 `model_version` 이하인지 확인한 뒤, 동일한 파일명을 내려줍니다(버전별로 파일명을 구분하지 않습니다).
4. 요청한 버전이 현재 버전보다 크거나 파일이 존재하지 않으면 `404`를 반환합니다.

### 사용 예시

#### 최신 모델 다운로드
```bash
curl -L -o cnn_gru_fatigue_latest.tflite \
  "https://merry99-musclecare-train-ai.hf.space/model"
```

#### 버전 3 모델 다운로드
```bash
curl -L -o cnn_gru_fatigue_v3.tflite \
  "https://merry99-musclecare-train-ai.hf.space/model?version=3"
```

#### 버전 3 메타데이터 다운로드
```bash
curl -L -o metadata_v3.json \
  "https://merry99-musclecare-train-ai.hf.space/model?version=3&filename=cnn_gru_fatigue_metadata.json"
```

#### 헤더 확인
```bash
curl -I "https://merry99-musclecare-train-ai.hf.space/model?version=3"
```
응답 헤더 예시:
```
X-Model-Version: 3
X-Model-Filename: cnn_gru_fatigue.tflite
```

### 주의 사항

- `training_state.json`의 `model_version` 값이 기준이 되며, 그보다 높은 버전을 요청하면 404가 반환됩니다.
- 버전별로 다른 파일을 유지하지 않고, 같은 파일명을 내려주되 헤더(`X-Model-Version`)로 실제 버전을 확인합니다.
- 실패(예: 404) 시 JSON 응답이 내려오므로, 클라이언트는 상태 코드를 먼저 확인한 뒤 **200일 때만** `body`를 파일로 저장하세요.

Flutter 예시 (Dio):
```dart
final response = await dio.get<List<int>>(
  'https://merry99-musclecare-train-ai.hf.space/model',
  options: Options(responseType: ResponseType.bytes),
);

if (response.statusCode == 200) {
  final version = response.headers.value('X-Model-Version');
  final filename = response.headers.value('X-Model-Filename') ?? 'model.tflite';
  await File('/path/$filename').writeAsBytes(response.data!);
} else {
  final errorText = utf8.decode(response.data ?? []);
  // 에러 처리
}
```
- Space 환경 변수 `HF_E2E_MODEL_TOKEN`, `HF_E2E_MODEL_REPO_ID`가 올바르게 설정돼 있어야 `/model` 및 `/trigger`가 정상 동작합니다.


## 모델 입력 사양 (Flutter 참고)

- 입력 형상: `(batch_size, input_dim)`이며 기본 `input_dim = 10 (FEATURE_COLUMNS) + embedding_dim`.
- `FEATURE_COLUMNS`: `rms_acc`, `rms_gyro`, `mean_freq_acc`, `mean_freq_gyro`, `entropy_acc`, `entropy_gyro`, `jerk_mean`, `jerk_std`, `stability_index`, `fatigue_prev`.
- `user_emb`: 메타데이터의 `embedding_dim`과 동일한 길이. 부족하면 뒤를 `0.0f`로 패딩.
- 메타데이터(`cnn_gru_fatigue_metadata.json`)의 `scaler.mean`, `scaler.scale`로 표준화한 뒤 모델에 전달.

### Flutter에서 실행 순서
- **메타데이터 로드**: JSON에서 `feature_columns`, `scaler.mean`, `scaler.scale`, `embedding_dim`, `input_dim`을 읽는다.
- **특징 추출**: 측정 버튼을 눌러 얻은 윈도우에서 10개 피처 값을 계산한다.
- **표준화**: `(value - mean) / scale`을 수행하되 `scale`이 0이면 0으로 대체.
- **입력 벡터 구성**: `[정규화된 10개 피처, user_emb(패딩 포함)]`을 이어 붙여 `Float32List`로 만든다.
- **TFLite 실행**: 입력을 `[1, input_dim]`으로 reshape 후 `interpreter.run(input, output)`을 호출한다.

```dart
final meta = await loadMetadata(); // JSON 파싱: scaler, embedding_dim 등
final features = computeFeatureVector(); // 길이 10, float
final userEmb = ensureEmbeddingLength(rawEmb, meta.embeddingDim); // 패딩

final normalized = List<double>.generate(features.length, (i) {
  final scale = meta.scalerScale[i] == 0 ? 1.0 : meta.scalerScale[i];
  return (features[i] - meta.scalerMean[i]) / scale;
});

final inputVector = Float32List.fromList([
  ...normalized,
  ...userEmb.map((e) => e.toDouble()),
]);

final outputBuffer = Float32List(1);
interpreter.run(inputVector.reshape([1, inputVector.length]), outputBuffer);
final fatigueScore = outputBuffer[0];
```

### 주의
- 최초 측정부터 바로 예측 가능하며, 더 이상 5개 윈도우 누적이 필요하지 않습니다.
- `fatigue_prev`는 직전 측정의 피로도 지표로, 값이 없다면 `0` 또는 직전 예측치로 초기화해 주세요.
- 피처 추출 로직과 임베딩 차원은 백엔드 학습 파이프라인과 동일해야 합니다.
