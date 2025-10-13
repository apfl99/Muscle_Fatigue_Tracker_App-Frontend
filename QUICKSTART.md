# 빠른 시작 가이드

## 1분 안에 앱 실행하기

### 1. 의존성 설치
```bash
flutter pub get
```

### 2. 환경 설정 (최소)

`lib/core/config/app_config.dart` 파일을 열고 다음 값들을 설정하세요:

```dart
// 임시로 기본값 사용 가능
static const String supabaseUrl = 'YOUR_SUPABASE_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
static const String apiBaseUrl = 'http://localhost:8000';
```

⚠️ **주의**: Supabase 설정이 없으면 로그인 기능이 작동하지 않습니다.
하지만 **"로그인 없이 계속하기"** 버튼으로 게스트 모드로 앱을 사용할 수 있습니다!

### 3. 앱 실행

```bash
# 연결된 기기 확인
flutter devices

# 앱 실행
flutter run
```

## 게스트 모드로 테스트하기

1. 앱 실행
2. 로그인 화면에서 **"로그인 없이 계속하기"** 클릭
3. "측정하기" 탭에서 **"측정 시작"** 클릭
4. 5초간 휴대폰을 쥐고 대기
5. 결과 확인!

## 다음 단계

### Supabase 설정 (로그인 기능 사용)

1. [Supabase](https://supabase.com/)에서 무료 프로젝트 생성
2. Project Settings > API에서 URL과 anon key 복사
3. `app_config.dart`에 붙여넣기
4. 앱 재시작

### 백엔드 API 연동 (서버 동기화 기능 사용)

1. FastAPI 백엔드 서버 실행
2. 서버 URL을 `app_config.dart`에 설정
3. 앱에서 로그인
4. 측정 결과가 자동으로 서버에 동기화됨

## 문제 해결

### "센서를 찾을 수 없습니다"
- 실제 기기에서 테스트하세요 (에뮬레이터는 센서 제한적)

### 빌드 오류
```bash
flutter clean
flutter pub get
flutter run
```

### iOS 빌드 오류
```bash
cd ios
pod install
cd ..
flutter run
```

## 주요 파일

- `lib/main.dart`: 앱 진입점
- `lib/core/config/app_config.dart`: 설정
- `lib/screens/`: UI 화면들
- `lib/services/`: 비즈니스 로직

더 자세한 내용은 `SETUP.md`와 `ARCHITECTURE.md`를 참고하세요!

