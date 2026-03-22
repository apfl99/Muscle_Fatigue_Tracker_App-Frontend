# MuscleCare Frontend (v2.0.0)

MuscleCare는 **Logging-First** 경험을 중심으로 동작하는 Flutter 앱입니다.  
사용자는 매일 운동을 기록하고, 3D 히트맵과 정밀 분석 화면을 통해 운동 수행 패턴 변화를 확인할 수 있습니다.

## 핵심 UX

- **메인 진입점:** `MainHomePage` (컨디션 로그 대시보드)
- **기록 플로우:** FAB 클릭 → 운동 검색(자동완성) → 운동 유형별 동적 폼 입력 → 컨디션 로그 저장
- **3D 시각화:** 저장 직후 3D 히트맵 색상 즉시 갱신
- **회복 예측:** `muscle_size(large/small)` 기반으로 근육별 예상 회복 시간 안내
- **정밀 분석 분리:** 기존 센서 분석은 `SensorAnalysisPage`로 분리
- **히스토리 IA 분리:** `운동 일지`(수기 기록) / `정밀 분석 리포트`(센서 데이터) 탭 분리
- **온보딩/리텐션:** 최초 웰컴 시트 + 연속 기록일(Streak) UI

## 기술 스택

- Flutter / Dart
- Supabase (`supabase_flutter`)
- 상태 관리: `provider` + `ChangeNotifier`
- 3D 뷰어: `model_viewer_plus`
- 광고: `google_mobile_ads`

## 3D 에셋 가이드

- 고해상도 근육 분리형 GLB 제작/구매 기준: `docs/3d_muscle_asset_spec.md`

## Supabase 인증 규칙

- 프론트는 **publishable key + 사용자 세션 JWT**만 사용합니다.
- 로그인 UI가 없어도 앱 시작 시 세션 확인 후 필요 시 `signInAnonymously()`로 세션을 생성합니다.
- `service_role`/`sb_secret` 키는 앱에 포함하지 않습니다.
- `get_muscle_heatmap_status` RPC 호출 시 `p_user_id`는 항상 현재 로그인 사용자 ID를 사용합니다.
- `search_exercises`는 사용자 입력 원문을 그대로 `p_keyword`로 전달합니다.

## 입력 규칙 (workout_logs)

- `exercise_type = cardio`: `duration_minutes` 필수, `sets/reps/weight_kg` 미입력
- `exercise_type = weight`: `sets/reps/weight_kg` 입력, `duration_minutes/distance_km` 선택
- 백엔드 400 메시지(`cardio logs require duration_minutes`, `weight logs require sets and reps`)를 사용자 안내 문구로 변환해 표시

## 빠른 시작

### 요구사항

- Flutter SDK 3.x
- Android Studio (Android 빌드)
- Xcode + CocoaPods (iOS 빌드)

### 설치

```bash
flutter pub get
```

```bash
cd ios && pod install && cd ..
```

### 실행

```bash
flutter run
```

## 테스트/검증 명령어

```bash
flutter analyze
flutter test
flutter test integration_test/app_flow_test.dart
```

```bash
flutter build apk --release
flutter build ios --release --no-codesign
```

## 주요 파일

- `lib/main.dart`
- `lib/screens/main_home_page.dart`
- `lib/screens/heatmap_full_viewer_page.dart`
- `lib/screens/sensor_analysis_page.dart`
- `lib/widgets/workout_log_bottom_sheet.dart`
- `lib/providers/heatmap_provider.dart`
- `lib/services/supabase_service.dart`
