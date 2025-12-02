# 근피로도 측정 앱

스마트폰 센서 기반 근피로도 웰니스 참고 지표 앱의 Flutter 프로젝트입니다.

> ⚠️ **의료 고지**: 이 앱의 근피로도 지표는 스마트폰 가속도·자이로 데이터를 활용한 웰니스 참고 정보입니다. 의료용 진단 장비가 아니며, 건강 상태 판단이나 치료 결정 전에 반드시 전문 의료진과 상담하세요.

## 시작하기

### 필요 사항
- Flutter SDK (3.0.0 이상)
- Android Studio / Xcode (각 플랫폼별 개발 환경)

### 설치 및 실행

1. 의존성 설치
```bash
flutter pub get
```

2. iOS 의존성 설치 (iOS 개발시)
```bash
cd ios
pod install
cd ..
```

3. 앱 실행
```bash
flutter run
```

## 프로젝트 구조

```
lib/
  └── main.dart          # 메인 애플리케이션 엔트리 포인트
test/
  └── widget_test.dart   # 위젯 테스트
```

## 개발 명령어

- `flutter run` - 앱 실행
- `flutter test` - 테스트 실행
- `flutter build apk` - Android APK 빌드
- `flutter build ios` - iOS 빌드
- `flutter clean` - 빌드 캐시 정리
