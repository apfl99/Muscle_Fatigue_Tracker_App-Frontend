# 프로젝트 설정 가이드

## 1. 초기 설정

### Flutter 환경 확인
```bash
flutter doctor
```

모든 체크마크가 표시되는지 확인하세요.

### 의존성 설치
```bash
flutter pub get
```

## 2. Supabase 설정

1. [Supabase](https://supabase.com/) 계정 생성
2. 새 프로젝트 생성
3. Project Settings > API에서 다음 정보 복사:
   - Project URL
   - anon public key

4. `lib/core/config/app_config.dart` 파일 수정:
```dart
static const String supabaseUrl = 'YOUR_PROJECT_URL';
static const String supabaseAnonKey = 'YOUR_ANON_KEY';
```

## 3. 백엔드 API 서버 설정

백엔드 서버가 준비되면:

1. 서버 URL을 `app_config.dart`에 설정:
```dart
static const String apiBaseUrl = 'http://YOUR_SERVER_IP:8000';
```

2. 로컬 테스트 시:
```dart
// Android 에뮬레이터
static const String apiBaseUrl = 'http://10.0.2.2:8000';

// iOS 시뮬레이터
static const String apiBaseUrl = 'http://localhost:8000';
```

## 4. 플랫폼별 설정

### iOS

1. `ios/Runner/Info.plist` 파일을 열고 다음 추가:

```xml
<key>NSMotionUsageDescription</key>
<string>근피로도 측정을 위해 센서 데이터 접근이 필요합니다.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>앱 사용 중 위치 정보 접근이 필요합니다.</string>
```

2. Cocoapods 설치 (아직 안 했다면):
```bash
cd ios
pod install
cd ..
```

### Android

1. `android/app/build.gradle` 파일에서 minSdkVersion 확인:
```gradle
minSdkVersion 21
```

2. 인터넷 권한은 자동으로 추가되지만, 확인:
`android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 5. 실행

### 디버그 모드
```bash
flutter run
```

### 릴리즈 모드
```bash
flutter run --release
```

### 특정 기기 지정
```bash
# 연결된 기기 목록
flutter devices

# 특정 기기에서 실행
flutter run -d <device-id>
```

## 6. 빌드

### Android APK
```bash
flutter build apk --release
```

생성 위치: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (Google Play용)
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

Xcode에서 Archive 진행

## 7. 개발 팁

### Hot Reload
앱 실행 중 코드 변경 후:
- `r` 키: Hot Reload
- `R` 키: Hot Restart

### 로그 확인
```bash
flutter logs
```

### 디버깅
VS Code나 Android Studio의 디버거 사용 권장

## 8. 문제 해결

### 빌드 오류 시
```bash
flutter clean
flutter pub get
```

### iOS Pods 문제
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
```

### Android Gradle 문제
```bash
cd android
./gradlew clean
cd ..
```

## 9. 환경별 실행

### Development
```bash
flutter run --dart-define=APP_ENV=development
```

### Production
```bash
flutter run --dart-define=APP_ENV=production \
            --dart-define=SUPABASE_URL=your_url \
            --dart-define=SUPABASE_ANON_KEY=your_key
```

## 10. 테스트

### 단위 테스트
```bash
flutter test
```

### 통합 테스트
```bash
flutter test integration_test/
```

## 11. 코드 분석
```bash
flutter analyze
```

## 12. 포맷팅
```bash
flutter format .
```

## 추가 리소스

- [Flutter 공식 문서](https://flutter.dev/docs)
- [Supabase 문서](https://supabase.com/docs)
- [Provider 문서](https://pub.dev/packages/provider)
- [sensors_plus 문서](https://pub.dev/packages/sensors_plus)

