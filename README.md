# 근피로도 측정 앱 (Muscle Fatigue Tracker)

스마트폰 내장 센서(가속도계, 자이로스코프)를 활용하여 사용자의 근피로도를 실시간으로 측정하고 시각화하는 Flutter 기반 모바일 애플리케이션입니다.

## 📱 주요 기능

### 1. 실시간 센서 기반 측정
- 스마트폰 IMU 센서(가속도계, 자이로스코프) 활용
- 5초간 100Hz 샘플링으로 센서 데이터 수집
- FFT, RMS, Variance, Dominant Frequency 실시간 분석

### 2. 온디바이스 ML 분석
- 로컬에서 센서 데이터 분석 수행
- 개인화된 Baseline 자동 학습 및 업데이트
- 0~10 스케일의 근피로 지수 산출

### 3. 데이터 시각화
- 실시간 측정 진행률 표시
- 게이지 차트로 피로도 수준 표시
- 시계열 그래프로 피로도 추세 확인

### 4. 로컬 저장 및 서버 동기화
- SQLite 기반 로컬 데이터 저장
- 로그인 시 Supabase 인증
- FastAPI 백엔드와 측정 결과 동기화

## 🏗️ 프로젝트 구조

```
lib/
├── core/                      # 핵심 설정 및 유틸리티
│   ├── config/
│   │   └── app_config.dart   # 앱 설정 (API URL, Supabase 키 등)
│   ├── constants/
│   │   └── app_constants.dart # 전역 상수
│   └── theme/
│       └── app_theme.dart    # 앱 테마 설정
├── models/                    # 데이터 모델
│   ├── sensor_data.dart      # 센서 데이터 모델
│   ├── fatigue_result.dart   # 피로도 측정 결과 모델
│   ├── user_baseline.dart    # 사용자 기준선 모델
│   └── user_model.dart       # 사용자 모델
├── services/                  # 비즈니스 로직 및 외부 연동
│   ├── sensor_service.dart   # 센서 데이터 수집
│   ├── analysis_service.dart # 피로도 분석 (RMS, FFT 등)
│   ├── local_storage_service.dart # 로컬 DB 관리
│   ├── api_service.dart      # API 통신
│   └── auth_service.dart     # 인증 관리
├── providers/                 # 상태 관리 (Provider)
│   ├── measurement_provider.dart # 측정 화면 상태
│   ├── auth_provider.dart    # 인증 상태
│   └── history_provider.dart # 측정 기록 상태
├── screens/                   # UI 화면
│   ├── login_screen.dart     # 로그인 화면
│   ├── home_screen.dart      # 홈 화면 (탭 네비게이션)
│   ├── measurement_screen.dart # 측정 화면
│   ├── result_screen.dart    # 결과 화면
│   ├── history_screen.dart   # 측정 기록 화면
│   └── profile_screen.dart   # 프로필 화면
├── widgets/                   # 재사용 가능한 위젯
└── main.dart                  # 앱 진입점
```

## 🚀 시작하기

### 필수 요구사항

- Flutter SDK: 3.0.0 이상
- Dart SDK: 3.0.0 이상
- Android Studio / Xcode (각 플랫폼별)
- iOS 12.0+ / Android 5.0+

### 설치 방법

1. **저장소 클론**
```bash
git clone <repository-url>
cd Muscle_Fatigue_Tracker_App-Frontend
```

2. **의존성 설치**
```bash
flutter pub get
```

3. **환경 설정**

`lib/core/config/app_config.dart` 파일에서 다음 설정을 업데이트하세요:

```dart
// Supabase 설정
static const String supabaseUrl = 'YOUR_SUPABASE_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

// API 서버 URL
static const String apiBaseUrl = 'http://YOUR_API_SERVER:8000';
```

또는 환경 변수로 설정:

```bash
flutter run --dart-define=SUPABASE_URL=your_url \
            --dart-define=SUPABASE_ANON_KEY=your_key \
            --dart-define=API_BASE_URL=your_api_url
```

4. **앱 실행**
```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# 디버그 모드
flutter run --debug

# 릴리즈 모드
flutter run --release
```

## 📊 측정 프로세스

1. **측정 시작**: "측정 시작" 버튼 클릭
2. **데이터 수집**: 5초간 센서 데이터 수집 (가속도계 + 자이로스코프)
3. **분석**: RMS, Variance, Dominant Frequency 계산
4. **피로도 계산**: 개인화된 Baseline 기반 피로도 지수 산출
5. **Baseline 업데이트**: 지수 이동 평균으로 사용자 기준선 갱신
6. **결과 저장**: 로컬 DB 저장 및 서버 동기화 (로그인 시)

## 🧮 피로도 계산 공식

```
Fatigue Index = α × (RMS / RMS_baseline) 
              + β × (Freq_baseline / Freq) 
              + γ × (Var / Var_baseline)

α = 3.0, β = 3.0, γ = 4.0
```

### Baseline 업데이트
```
Baseline_new = (1 - λ) × Baseline_old + λ × Current_value
λ = 0.2 (20% 새 값, 80% 기존 값)
```

## 📦 주요 패키지

- `sensors_plus`: 센서 데이터 수집
- `fl_chart`: 그래프 시각화
- `syncfusion_flutter_gauges`: 게이지 차트
- `provider`: 상태 관리
- `sqflite`: 로컬 데이터베이스
- `supabase_flutter`: 인증 및 백엔드 연동
- `dio`: HTTP 통신

## 🔐 인증 및 데이터 관리

### 게스트 모드
- 로그인 없이 앱 사용 가능
- 측정 데이터는 로컬에만 저장
- Baseline은 로컬에서 관리

### 로그인 모드
- Supabase 인증 사용
- 측정 결과 서버 동기화
- 여러 기기에서 데이터 접근 가능
- 주간 통계 및 리포트 제공

## 🛠️ 개발 가이드

### 새로운 화면 추가

1. `lib/screens/` 폴더에 화면 파일 생성
2. 필요한 경우 `lib/providers/`에 Provider 생성
3. `lib/main.dart`의 라우트에 추가

### 새로운 API 엔드포인트 추가

1. `lib/services/api_service.dart`에 메서드 추가
2. 필요한 경우 모델 파일 생성

### 테스트

```bash
# 단위 테스트
flutter test

# 통합 테스트
flutter test integration_test/
```

## 📱 플랫폼별 설정

### iOS
- `ios/Runner/Info.plist`에 센서 권한 추가 필요:
```xml
<key>NSMotionUsageDescription</key>
<string>근피로도 측정을 위해 센서 접근이 필요합니다.</string>
```

### Android
- `android/app/src/main/AndroidManifest.xml`에 권한 자동 추가됨
- 인터넷 권한 확인:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 🐛 문제 해결

### 센서 데이터가 수집되지 않을 때
- 기기가 센서를 지원하는지 확인
- 앱 권한 설정 확인
- 에뮬레이터에서는 센서 데이터가 제한적일 수 있음

### 빌드 오류
```bash
# 캐시 정리
flutter clean
flutter pub get

# iOS Pods 재설치
cd ios
pod deintegrate
pod install
cd ..
```

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 🤝 기여

버그 리포트, 기능 제안, Pull Request는 언제나 환영합니다!

## 📞 문의

프로젝트 관련 문의사항이 있으시면 이슈를 등록해주세요.
