# MuscleCare v2.0.0 전면 개편 리포트

## 1) 구현 범위 요약

- 메인 진입점을 `MainHomePage`(Logging-First 대시보드)로 변경
- `SupabaseService` + `HeatmapProvider` 기반으로 검색/저장/히트맵 상태 동기화 구성
- 3D 미리보기/풀뷰어(`model_viewer_plus`) 추가 및 상태 색상 0.8초 전환 적용
- 수기 컨디션 로그 입력 바텀시트(자동완성 Debounce 500ms, Auto-focus, Numpad) 추가
- 기록 성공 시 `HapticFeedback.mediumImpact()` 적용
- 측정(센서) 기능을 정밀 분석 진입 흐름으로 분리(`SensorAnalysisPage` 래퍼)
- 히스토리 화면에 수기 로그(초록+덤벨) vs 센서 정밀 분석(블루/퍼플+파동) 시각 분리
- `README.md`, `CHANGELOG.md` 업데이트

## 2) PM 요구사항 반영

- 온보딩: `shared_preferences` 기반 1회성 웰컴 바텀시트 적용
- 리텐션: 메인 상단 Streak UI(`🔥 00일차`) 적용
- 광고: `MainHomePage`/`HeatmapFullViewerPage` 하단 자연 노출, 센서 화면 기존 로직 유지
- 퍼널 이벤트: `on_fab_clicked` / `on_exercise_searched` / `on_log_saved_success` 로그 출력

## 3) 디자이너 요구사항 반영

- 다크 테마: `#0A0E27` / Primary Green `#00E676` / 카드 반경 `20` 적용
- 3D 상태 색상 전환: `AnimatedContainer(duration: 800ms)`로 페이드 전환
- Empty State 유도: FAB 방향 펄스 화살표 적용
- 입력 UX: 검색창 Auto-focus, 숫자 입력 필드 Number Pad 적용

## 4) 품질/검증 결과

### 단위 테스트

```bash
flutter test
```

- 결과: 성공 (`All tests passed`)

### 통합 테스트

```bash
flutter test integration_test/app_flow_test.dart
```

- 결과: 실패 (환경 제약)
- 실패 사유: 실행 가능한 모바일 디바이스 미연결
- 로그 요약: `No supported devices connected.`

### Android 릴리즈 빌드

```bash
flutter build apk --release
```

- 결과: 성공
- 로그 요약:
  - `Running Gradle task 'assembleRelease'... 307.8s`
  - `✓ Built build/app/outputs/flutter-apk/app-release.apk (78.2MB)`

### iOS 릴리즈 빌드 (무서명)

```bash
flutter build ios --release --no-codesign
```

- 결과: 성공
- 로그 요약:
  - `Running pod install... 5.0s`
  - `Xcode build done. 220.8s`
  - `✓ Built build/ios/iphoneos/Runner.app (40.6MB)`

## 5) 파일 단위 산출물

- 인프라/상태:
  - `pubspec.yaml`
  - `lib/services/supabase_service.dart`
  - `lib/providers/heatmap_provider.dart`
- 분리/라우팅:
  - `lib/main.dart`
  - `lib/screens/sensor_analysis_page.dart`
- 신규 UI:
  - `lib/screens/main_home_page.dart`
  - `lib/widgets/workout_log_bottom_sheet.dart`
- 3D/히스토리:
  - `lib/screens/heatmap_full_viewer_page.dart`
  - `lib/screens/measurement_history_page.dart`
- QA/문서:
  - `integration_test/app_flow_test.dart`
  - `README.md`
  - `CHANGELOG.md`
