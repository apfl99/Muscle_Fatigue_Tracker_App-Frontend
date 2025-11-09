# Worker 시스템 사용 가이드

이 폴더에는 측정 완료 후 데이터를 서버로 비동기 전송하는 워커 시스템이 포함되어 있습니다.

## 📁 파일 구조

```
lib/worker/
├── measurement_task.dart    # 측정 작업 데이터 모델
├── server_config.dart       # 서버 설정 관리
├── data_converter.dart      # SQLite → JSON 변환기
├── queue_manager.dart       # 비동기 큐 관리자
├── http_worker.dart         # HTTP 전송 워커
├── worker_manager.dart      # 워커 매니저
└── README.md               # 이 파일
```

## 🚀 사용 방법

### 1. 기본 설정

```dart
// 서버 설정
final serverConfig = await getServerConfig();
serverConfig.apiBaseUrl = 'https://your-api-space.hf.space';
serverConfig.modelBaseUrl = 'https://your-model-space.hf.space';
await updateServerConfig(serverConfig);

// 워커 매니저 초기화
await initializeWorkerManager();
```

### 2. 측정 완료 후 데이터 전송

```dart
// 단일 측정 데이터 전송
final workerManager = await getWorkerManager();
await workerManager.addMeasurementTask(
  userId: 'user123',
  sessionId: 'session456',
  measurementData: {
    'rms': 0.1234,
    'freq': 45.67,
    'fatigue': 0.789,
    'mode': 'EMA',
    'window_count': 10,
    'measure_date': '2024-01-15',
  },
);

// 사용자 상태 전송
await workerManager.addUserStateTask(
  userId: 'user123',
);
```

### 3. 동기화되지 않은 데이터 일괄 전송

```dart
// 모든 동기화되지 않은 데이터를 큐에 추가
await workerManager.addUnsyncedDataToQueue(
  userId: 'user123',  // 특정 사용자만 (선택사항)
  useBatch: true,     // 배치 처리 사용
);
```

### 4. 상태 확인

```dart
// 큐 상태 확인
final status = workerManager.getQueueStatus();
print('대기 중: ${status['queue_stats']['pending']}');

// 동기화 통계 확인
final syncStats = await workerManager.getSyncStats(userId: 'user123');
print('동기화되지 않은 데이터: ${syncStats['database']['unsynced']}');
```

## ⚙️ 설정 옵션

### 서버 설정 (server_config.dart)

```dart
final config = ServerConfig(
  baseUrl: 'https://your-server.com',
  apiVersion: 'v1',
  timeoutSeconds: 30,
  maxRetries: 3,
  enableLogging: true,
);
```

### 큐 설정 (queue_manager.dart)

- **최대 큐 크기**: 1000개 작업
- **최대 재시도**: 3회
- **우선순위**: 1(높음) ~ 5(낮음)

## 🔄 데이터 흐름

1. **측정 완료** → SQLite에 저장
2. **큐에 작업 추가** → `addMeasurementTask()` 호출
3. **워커가 큐에서 작업 가져오기** → 순차 처리
4. **HTTP로 서버 전송** → Oracle DB에 저장
5. **동기화 완료 처리** → `synced = 1`로 업데이트

## 📊 모니터링

```dart
// 상태 출력
workerManager.printStatus();

// 서버 연결 확인
final isHealthy = await workerManager.checkServerHealth();
```

## 🛠️ 문제 해결

### 큐가 멈춘 경우
```dart
// 처리 중인 작업들을 대기 상태로 복원
await queueManager.resetProcessingTasks();
```

### 큐 초기화
```dart
// 모든 큐 데이터 삭제
await queueManager.clearQueue();
```

### 서버 연결 실패
- 서버 URL 확인
- 네트워크 연결 확인
- 서버 상태 확인 (`/health` 엔드포인트)

## 📝 로그

모든 작업은 콘솔에 로그가 출력됩니다:
- 📝 작업 추가
- 🔧 작업 처리 시작
- ✅ 작업 완료
- ❌ 작업 실패
- 🔄 작업 재시도

## 🔧 커스터마이징

### 새로운 작업 타입 추가

1. `measurement_task.dart`에서 새로운 데이터 타입 정의
2. `http_worker.dart`에서 처리 로직 추가
3. `data_converter.dart`에서 변환 로직 추가

### 배치 크기 변경

```dart
// data_converter.dart에서
final batchTasks = await _dataConverter.convertToBatchTasks(
  batchSize: 10, // 기본값: 5
);
```
