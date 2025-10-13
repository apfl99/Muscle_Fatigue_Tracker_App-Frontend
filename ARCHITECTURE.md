# 프로젝트 아키텍처

## 전체 구조

이 프로젝트는 **Clean Architecture** 원칙을 따르며, **Provider 패턴**을 사용한 상태 관리를 채택했습니다.

```
┌─────────────────────────────────────────────┐
│              Presentation Layer             │
│  (Screens, Widgets, Providers)              │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│              Business Logic Layer           │
│  (Services, Analysis)                       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│              Data Layer                     │
│  (Models, Local Storage, API)               │
└─────────────────────────────────────────────┘
```

## 레이어별 설명

### 1. Presentation Layer (UI)

**책임**: 사용자 인터페이스 렌더링 및 사용자 입력 처리

#### Screens
- `login_screen.dart`: 로그인/회원가입
- `home_screen.dart`: 탭 네비게이션 메인 화면
- `measurement_screen.dart`: 측정 화면
- `result_screen.dart`: 측정 결과 표시
- `history_screen.dart`: 측정 기록 목록
- `profile_screen.dart`: 사용자 프로필

#### Providers (상태 관리)
- `MeasurementProvider`: 측정 프로세스 상태 관리
  - 센서 데이터 수집
  - 진행률 추적
  - 분석 결과 관리
  
- `AuthProvider`: 인증 상태 관리
  - 로그인/로그아웃
  - 사용자 세션 관리
  
- `HistoryProvider`: 측정 기록 관리
  - 로컬 데이터 로드
  - 서버 동기화

### 2. Business Logic Layer

**책임**: 핵심 비즈니스 로직 및 데이터 처리

#### Services

##### SensorService
- 센서 데이터 실시간 수집
- 가속도계 + 자이로스코프 통합
- 스트림 기반 데이터 전달

```dart
void startListening()      // 센서 수집 시작
void stopListening()       // 센서 수집 중지
Stream<SensorData> get sensorDataStream  // 데이터 스트림
```

##### AnalysisService
- 센서 데이터 분석
- 피로도 지수 계산
- Baseline 기반 개인화

주요 분석 메트릭:
- **RMS (Root Mean Square)**: 진동 크기
- **Variance**: 움직임 변동성
- **Dominant Frequency**: 주요 진동 주파수

```dart
Future<FatigueResult> analyzeFatigue({
  required List<SensorData> sensorData,
  required UserBaseline baseline,
  String? userId,
})
```

##### LocalStorageService
- SQLite 기반 로컬 DB 관리
- SharedPreferences 설정 저장
- Baseline 영속화

##### ApiService
- FastAPI 백엔드 통신
- 측정 결과 업로드
- 통계 데이터 조회

##### AuthService
- Supabase 인증 연동
- 사용자 세션 관리

### 3. Data Layer

**책임**: 데이터 모델 정의 및 저장소 접근

#### Models

##### SensorData
센서 원시 데이터
```dart
{
  timestamp: DateTime,
  accelerometerX/Y/Z: double,
  gyroscopeX/Y/Z: double
}
```

##### FatigueResult
피로도 측정 결과
```dart
{
  id: String,
  timestamp: DateTime,
  fatigueIndex: double,  // 0~10
  rms: double,
  variance: double,
  dominantFrequency: double,
  userId: String?
}
```

##### UserBaseline
사용자별 기준선
```dart
{
  userId: String,
  rmsBaseline: double,
  varianceBaseline: double,
  frequencyBaseline: double,
  lastUpdated: DateTime,
  measurementCount: int
}
```

## 데이터 흐름

### 측정 프로세스

```
1. 사용자 버튼 클릭
   ↓
2. MeasurementProvider.startMeasurement()
   ↓
3. SensorService.startListening()
   → 5초간 센서 데이터 수집 (100Hz)
   ↓
4. 500개 샘플 수집 완료
   ↓
5. AnalysisService.analyzeFatigue()
   → RMS, Variance, DominantFreq 계산
   → Baseline과 비교하여 피로도 계산
   ↓
6. UserBaseline 업데이트 (지수 이동 평균)
   ↓
7. LocalStorageService.saveFatigueResult()
   ↓
8. (로그인 시) ApiService.uploadFatigueResult()
   ↓
9. 결과 화면 표시
```

### 상태 관리 흐름

```
UI 이벤트
  ↓
Provider (notifyListeners)
  ↓
Consumer 위젯 리빌드
  ↓
화면 업데이트
```

## 피로도 계산 알고리즘

### 1단계: 메트릭 계산

```dart
// RMS 계산
RMS = sqrt(Σ(magnitude²) / N)

// Variance 계산
Variance = Σ((x - mean)²) / N

// Dominant Frequency 추정
DominantFreq ≈ ZeroCrossingRate / 2
```

### 2단계: 정규화

```dart
rmsRatio = RMS / RMS_baseline
varRatio = Variance / Variance_baseline
freqRatio = Freq_baseline / Freq  // 역수 (주파수 낮을수록 피로)
```

### 3단계: 피로도 지수 계산

```dart
FatigueIndex = α × rmsRatio + β × freqRatio + γ × varRatio
```

가중치: α=3.0, β=3.0, γ=4.0

### 4단계: Baseline 업데이트

```dart
Baseline_new = (1-λ) × Baseline_old + λ × Current_value
```

λ = 0.2 (20% 새 값 반영)

## 확장 가능성

### 향후 추가 가능 기능

1. **고급 ML 모델**
   - TFLite 모델 통합
   - On-device 딥러닝 추론

2. **실시간 피드백**
   - 측정 중 실시간 그래프
   - 햅틱 피드백

3. **소셜 기능**
   - 그룹 챌린지
   - 리더보드

4. **웨어러블 연동**
   - Apple Watch
   - Galaxy Watch

5. **고급 분석**
   - 주간/월간 리포트
   - 예측 모델
   - 운동 추천

## 성능 최적화

### 센서 데이터 수집
- 버퍼링으로 UI 블로킹 방지
- Isolate 활용 가능 (필요시)

### 로컬 DB
- 인덱스 최적화
- 배치 작업 최소화

### UI 렌더링
- const 위젯 활용
- ListView.builder 사용
- 불필요한 rebuild 방지

## 보안 고려사항

1. **데이터 프라이버시**
   - 센서 데이터는 서버 전송 안 함
   - 분석 결과만 업로드

2. **인증**
   - Supabase Row Level Security
   - JWT 토큰 기반 인증

3. **로컬 저장소**
   - 민감 정보 암호화 (필요시)
   - 안전한 키 저장

## 테스트 전략

### 단위 테스트
- 모델 클래스 JSON 변환
- 분석 알고리즘 정확성
- Baseline 업데이트 로직

### 통합 테스트
- 센서 → 분석 → 저장 전체 플로우
- API 통신

### 위젯 테스트
- 화면별 UI 렌더링
- 사용자 인터랙션

### E2E 테스트
- 전체 측정 프로세스
- 로그인 → 측정 → 기록 확인

