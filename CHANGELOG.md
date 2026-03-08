# Changelog

## v2.0.1 - 2026-03-06

### Hotfix
- v2.0.1 핫픽스: 광고 시스템 안정화 및 피로도 시각화 UX 개편

### Added
- 스플래시 전면광고 플로우 복구: 광고 준비 시 노출, 3초 초과 시 즉시 메인 진입
- 공통 `BannerAdWidget` 도입(화면별 배너 인스턴스 분리, 로드/표시/해제 캡슐화)
- 히스토리 상/하 분할 대시보드 추가(상단 추이/캘린더 토글 + 하단 통합 타임라인 Sliver)

### Changed
- 히트맵 전체 뷰어를 3D 모델에서 2D 해부학 SVG + 동적 배경 그라데이션(1초 애니메이션)으로 전환
- 메인 홈 미리보기도 2D 기반 시각화로 정리하여 더미 우주비행사 노출 제거
- 앱 메인 진입점을 `SplashScreen`으로 복구

### Fixed
- `This AdWidget is already in the Widget tree` 크래시 수정(싱글톤 BannerAd 재사용 구조 제거)
- Android `ERR_CLEARTEXT_NOT_PERMITTED` 대응(`AndroidManifest.xml` cleartext 설정 유지)

## v2.0.0 - 2026-03-01

### Added
- Logging-First 홈 대시보드(`MainHomePage`) 추가
- 3D 히트맵 전체 뷰어(`HeatmapFullViewerPage`) 추가
- 컨디션 로그 입력 바텀시트(`WorkoutLogBottomSheet`) 추가
- Supabase 연동 서비스(`supabase_service.dart`) 추가
- 전역 상태 관리(`heatmap_provider.dart`) 추가
- 통합 시나리오 테스트(`integration_test/app_flow_test.dart`) 추가

### Changed
- 앱 진입점을 `MainHomePage`로 변경
- 기존 센서 화면을 정밀 분석 진입 흐름으로 분리
- 메인/히스토리 화면에 수기 로그 vs 센서 정밀 분석 기록 시각적 분리 적용
- 다크 테마를 `UI_DESIGN_GUIDE.md` 기준(`#0A0E27`, Primary Green, 카드 radius 20)으로 정렬
- 문구를 의료 용어 중심에서 `운동 수행 패턴 분석`/`컨디션 로그`/`정밀 분석` 중심으로 조정

### Infra
- `model_viewer_plus`, `provider` 의존성 추가
- iOS 모션 권한 안내 문구 업데이트
