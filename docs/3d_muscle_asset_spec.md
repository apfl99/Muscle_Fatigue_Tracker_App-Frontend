# 3D Muscle Asset Spec (High-End Interactive Viewer)

이 문서는 `InteractiveMuscle3DViewer`에서 사용하는 해부학 바디맵 에셋의 구매/제작 기준이다.  
핵심 목적은 **근육 그룹 간 경계를 육안으로 명확하게 분리**하고, 앱에서 메쉬/머티리얼 단위로 즉시 컬러 주입하는 것이다.

## 1) 필수 파일 포맷/성능

- 포맷: `.glb` (glTF 2.0 binary)
- 폴리곤: **50k 이하**
- 텍스처: 최대 2K, 권장 1K (모바일 메모리 안정성)
- 재질: PBR(Material) 유지, 금속도/거칠기 조절 가능 구조
- 좌표계: 기본 T-pose 기준, 정면 기준 yaw=0

## 2) Visual Separation 필수 조건

- 각 근육 메쉬는 **물리적으로 분리된 독립 파트**여야 한다.
- 메쉬 경계부에 다음 중 최소 1개 이상이 반드시 적용되어야 한다.
  - 깊은 크리비스(틈) 지오메트리
  - AO(ambient occlusion) 기반 경계 음영
  - 경계 질감(outline-like dark ridge)
- 경계가 흐려서 인접 근육이 한 덩어리로 보이는 모델은 불합격.

## 3) 네이밍 컨벤션 (영문 ID 강제)

- Node/Mesh: `node_<muscle_code>`
  - 예: `node_chest`, `node_quadriceps`, `node_latissimus`
- Material: `Material_<Region>`
  - 예: `Material_Chest`, `Material_Quads`, `Material_Lats`
- 금지: 한글, 공백, 하이픈 난립, 의미 없는 숫자 접미사

## 4) Flutter/JS 매핑 계약

- Dart 운동부위 ID와 GLB 내부 이름이 매핑 가능해야 함:
  - `muscle_code -> material_name`
  - (선택) `mesh_name -> muscle_code`
- 런타임에서는 **모델 재로딩 없이** `setBaseColorFactor`로 색상만 변경한다.
- 컬러 범위: 네온 그린 `#00F58A` ~ 레드 그라데이션.

## 5) 개발용 Mock URL (에셋 준비 전)

- 임시 src:
  - `https://raw.githubusercontent.com/msorkhpar/3d-human-model-vite/main/body.glb`
- 참고:
  - 무료 공개 URL이라 로컬 에셋 부재 시 즉시 렌더링 테스트 가능
  - 상용 최종본은 위 1~4 조건을 만족하는 전용 분할 근육 모델로 대체 필요

## 6) 납품 전 체크리스트

- [ ] 3D 모델 로딩 5초 이내(중급 기기 기준)
- [ ] 근육 경계가 명확히 구분됨(암부/틈새 식별 가능)
- [ ] `materialFromPoint()` 탭 시 부위 ID 추적 가능
- [ ] 메쉬 컬러 업데이트 시 전체 모델 재로딩 없음
- [ ] OOM/프레임 드랍 없는지 10분 회전 테스트 통과

## 7) 보조 스크립트

- `tools/segment_glb_materials.py`
  - 단일 재질 GLB를 근육/영역별 다중 재질로 분리할 때 사용
  - 지오메트리 버퍼는 유지하고 material index만 재작성
