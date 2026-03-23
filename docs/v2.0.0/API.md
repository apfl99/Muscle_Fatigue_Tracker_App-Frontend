# REQ-30 근육 피로도 히트맵 API/스키마 명세

## 1) 개요

최근 운동 기록(`workout_logs`)을 기반으로 근육별 히트맵 상태를 반환합니다.

- `red`: 최근 24시간 내 운동 기록 있음
- `yellow`: 24~48시간 경과
- `green`: 48시간 이상 경과 또는 기록 없음

주동근(`primary`)과 협응근(`secondary`) 모두 피로도 계산에 반영됩니다.

추가로 운동 검색 자동완성을 위해 `search_exercises` RPC가 제공됩니다.

---

## 2) 배포 SQL 파일

- 스키마/인덱스/RLS/RPC: `supabase/req30_heatmap_schema.sql`
- 방대한 Seed(250 운동 + 근육 매핑): `supabase/req30_heatmap_seed.sql`
- 검색 최적화(pg_trgm/Gin/RPC): `supabase/req30_search_optimization.sql`
- 검색 확장(한글/초성/동의어): `supabase/migrations/20260301052000_req30_search_korean_synonyms.sql`
- V2 고도화(유산소/무산소 분리 + 로그 유연화): `supabase/migrations/20260301070000_req30_v2_cardio_weight_split.sql`
- 해부학 JSON 업그레이드(근육 배열/히트맵 가중치): `supabase/migrations/20260305142000_req30_anatomy_json_upgrade.sql`
- 근육 표준화/placeholder 제거/계약 강화: `supabase/migrations/20260308100000_req30_muscle_standardization.sql`

권장 실행 순서:

1. `req30_heatmap_schema.sql`
2. `req30_heatmap_seed.sql`
3. `req30_search_optimization.sql`
4. `20260301052000_req30_search_korean_synonyms.sql`
5. `20260301070000_req30_v2_cardio_weight_split.sql`
6. `20260305142000_req30_anatomy_json_upgrade.sql`
7. `20260308100000_req30_muscle_standardization.sql`

---

## 3) ERD (텍스트)

- `auth.users (1)` -> `(N) workout_logs`
- `exercises (1)` -> `(N) workout_logs`
- `exercises (1)` -> `(N) exercise_muscle_mapping`
- `exercises (1)` -> `(N) exercise_search_aliases`
- `muscles (1)` -> `(N) exercise_muscle_mapping`

히트맵 계산 시 기본 경로는
`workout_logs.exercise_id -> exercises.primary_muscles/secondary_muscles -> muscles` 이며,
`exercise_muscle_mapping`은 참조/호환용 브릿지 테이블로 유지됩니다.

---

## 4) 테이블 정의서

### `public.muscles`

- `id uuid PK`
- `code text UNIQUE NOT NULL` (소문자 snake_case, SVG Path ID와 1:1 매핑)
- `display_name text NOT NULL`
- `display_name_ko text NOT NULL` (placeholder 금지)
- `display_name_latin text NULL`
- `anatomy_id text NULL` (FMA/UBERON 등 표준 ID 확장 필드)
- `parent_muscle_code text NULL` (`muscles.code` self FK)
- `side text NOT NULL DEFAULT 'bilateral'` (`left|right|bilateral|unknown`)
- `display_order integer NOT NULL DEFAULT 0`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### `public.muscle_code_aliases`

- `alias_code text PK` (정규화된 별칭 코드)
- `muscle_code text NOT NULL FK -> muscles(code)`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### `public.exercises`

- `id uuid PK`
- `slug text UNIQUE NOT NULL` (소문자 snake_case)
- `name text NOT NULL`
- `category text NOT NULL`
- `exercise_type varchar NOT NULL` (`cardio` | `weight`)
- `muscle_size varchar NOT NULL` (`large` | `small`)
- `primary_muscles text[] NOT NULL DEFAULT '{}'`
- `secondary_muscles text[] NOT NULL DEFAULT '{}'`
- `equipment text NOT NULL`
- `biomechanics_note text NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### `public.exercise_muscle_mapping`

- `id uuid PK`
- `exercise_id uuid FK -> exercises(id) ON DELETE CASCADE`
- `muscle_id uuid FK -> muscles(id) ON DELETE CASCADE`
- `role text NOT NULL CHECK role in ('primary','secondary')`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`
- `UNIQUE (exercise_id, muscle_id)`

### `public.exercise_search_aliases`

- `id uuid PK`
- `exercise_id uuid FK -> exercises(id) ON DELETE CASCADE`
- `alias text NOT NULL`
- `alias_type text NOT NULL` (`ko`, `synonym`, `abbr`, `keyword`)
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`
- `UNIQUE (exercise_id, alias)`

### `public.workout_logs`

- `id uuid PK`
- `user_id uuid FK -> auth.users(id) ON DELETE CASCADE`
- `exercise_id uuid FK -> exercises(id) ON DELETE RESTRICT`
- `sets integer NULL CHECK sets > 0`
- `reps integer NULL CHECK reps > 0`
- `weight_kg numeric(6,2) NULL CHECK weight_kg >= 0`
- `duration_minutes integer NULL CHECK duration_minutes > 0`
- `distance_km numeric(8,3) NULL CHECK distance_km >= 0`
- `note text NULL`
- `performed_at timestamptz NOT NULL DEFAULT now()`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### 필수 인덱스

- `idx_workout_logs_user_id (user_id)`
- `idx_workout_logs_created_at (created_at desc)`
- `idx_workout_logs_user_created_at (user_id, created_at desc)`
- `idx_exercises_exercise_type (exercise_type)`
- `idx_exercises_muscle_size (muscle_size)`
- `idx_exercises_primary_muscles_gin (gin, primary_muscles)`
- `idx_exercises_secondary_muscles_gin (gin, secondary_muscles)`
- `idx_muscles_anatomy_id_unique (anatomy_id) where anatomy_id is not null`
- `idx_muscles_parent_muscle_code (parent_muscle_code)`
- `idx_exercises_name_trgm (gin, name gin_trgm_ops)`
- `idx_exercises_name_norm_trgm (gin, search_normalize_text(name) gin_trgm_ops)`
- `idx_exercise_aliases_alias_trgm (gin, alias gin_trgm_ops)`
- `idx_exercise_aliases_alias_norm_trgm (gin, search_normalize_text(alias) gin_trgm_ops)`
- `idx_exercise_aliases_alias_choseong_trgm (gin, hangul_to_choseong(alias) gin_trgm_ops)`

성능 보조 인덱스:

- `idx_workout_logs_user_performed_at (user_id, performed_at desc)`
- `idx_workout_logs_exercise_id (exercise_id)`
- `idx_exercise_muscle_mapping_exercise_id (exercise_id)`
- `idx_exercise_muscle_mapping_muscle_id (muscle_id)`

---

## 5) RLS 정책

### Reference Table (`muscles`, `muscle_code_aliases`, `exercises`, `exercise_muscle_mapping`)

- `SELECT`만 `authenticated`에 허용
- `INSERT/UPDATE/DELETE` 정책 없음 (기본 거부)

### User Data (`workout_logs`)

- `SELECT`: `auth.uid() = user_id`
- `INSERT`: `with check (auth.uid() = user_id)`
- `UPDATE`: `using/auth.uid() = user_id` + `with check/auth.uid() = user_id`
- `DELETE`: `auth.uid() = user_id`

즉, 사용자는 본인 운동 기록만 조회/생성/수정/삭제할 수 있습니다.

### 입력 무결성 규칙 (`workout_logs`)

- `exercise_type = 'cardio'`인 운동 기록은 `duration_minutes`가 필수
- `exercise_type = 'weight'`인 운동 기록은 `sets`와 `reps`가 필수
- 위 규칙은 DB Trigger(`validate_workout_log_payload_by_exercise_type`)로 강제

---

## 6) RPC 명세 (Swagger 스타일)

### 6-1) `get_muscle_heatmap_status`

### Endpoint

- `POST /rest/v1/rpc/get_muscle_heatmap_status`

### Headers

- `apikey: <sb_publishable_xxx>`
- `Authorization: Bearer <user_access_token>`
- `Content-Type: application/json`

### Request Body

```json
{
  "p_user_id": "9a8e7f1c-1111-2222-3333-444455556666"
}
```

### Success Response (200)

```json
[
  {
    "muscle": "quadriceps",
    "muscle_code": "quadriceps",
    "display_name_ko": "대퇴사두근",
    "display_name_latin": "Musculus quadriceps femoris",
    "anatomy_id": null,
    "parent_muscle_code": null,
    "side": "bilateral",
    "status": "red",
    "fatigue_score": 2.0,
    "last_trained_at": "2026-03-08T08:04:59.08414+00:00"
  },
  {
    "muscle": "calves",
    "muscle_code": "calves",
    "display_name_ko": "종아리",
    "display_name_latin": "Musculus gastrocnemius",
    "anatomy_id": null,
    "parent_muscle_code": null,
    "side": "bilateral",
    "status": "yellow",
    "fatigue_score": 1.0,
    "last_trained_at": "2026-03-08T08:04:59.08414+00:00"
  }
]
```

`status` enum:

- `red`
- `yellow`
- `green`

히트맵 계산 규칙:

- 주동근(`primary_muscles`) 가중치: `1.0`
- 협응근(`secondary_muscles`) 가중치: `0.5`
- 시간 감쇠:
  - 24h 이내: `1.00`
  - 24~48h: `0.60`
  - 48~72h: `0.30`
  - 72h~7d: `0.15`
  - 7d~14d: `0.05`
- 근육별 `fatigue_score = Σ(역할가중치 × 시간감쇠)`
- 응답 보장:
  - `muscle_code`: 항상 `^[a-z0-9_]+$` 준수
  - `display_name_ko`: placeholder(`근육부위`, `기타 근육`, `Unknown`, `Other`) 미반환
  - 레거시 호환을 위해 `muscle` 필드는 `muscle_code`와 동일값 유지

### Error Responses

- `404 PGRST202`: 함수가 배포되지 않았거나 schema cache에 없음
- `403 bad_jwt`: 잘못된 JWT 형식
- `403 (42501)`: `p_user_id`가 현재 로그인 사용자와 다름

### 6-2) `search_exercises`

### Endpoint

- `POST /rest/v1/rpc/search_exercises`

### Headers

- `apikey: <sb_publishable_xxx>`
- `Authorization: Bearer <user_access_token>`
- `Content-Type: application/json`

### Request Body

```json
{
  "p_keyword": "스쿼트"
}
```

### Success Response (200)

```json
[
  {
    "id": "921a01bb-c59d-4f19-9190-fc4ea6e3af32",
    "name": "Back Squat",
    "category": "free_weight",
    "exercise_type": "weight",
    "muscle_size": "large",
    "primary_muscles": ["quadriceps"],
    "secondary_muscles": ["calves", "glutes", "hamstrings", "lower_back"]
  },
  {
    "id": "f4e61aa5-c49d-4b41-9702-4fd4a69e4c46",
    "name": "Front Squat",
    "category": "free_weight",
    "exercise_type": "weight",
    "muscle_size": "large",
    "primary_muscles": ["quadriceps"],
    "secondary_muscles": ["calves", "glutes", "hamstrings"]
  }
]
```

동작 규칙:

- 검색 대상:
  - `exercises.name` (영문 공식명)
  - `exercise_search_aliases.alias` (한글명/동의어/약어)
- 매칭 방식:
  - 부분 일치(`ILIKE`)
  - 정규화 문자열 비교(`search_normalize_text`)
  - 초성 비교(`hangul_to_choseong`)
- 정렬: `similarity` 점수 기반 내림차순
- 최대 `20`개 제한
- 공백/빈 문자열 키워드 입력 시 빈 배열 반환

예시 키워드:

- 영문: `squat`
- 한글: `스쿼트`, `벤치프레스`
- 초성: `ㅅㅋㅌ`

### Error Responses

- `401/403`: 인증 실패 또는 권한 없음
- `400`: 잘못된 파라미터 형식

---

## 7) 프론트엔드 연동 체크리스트

1. 앱에서 로그인 세션의 `user.id`를 확보
2. 히트맵 RPC 호출 시 `p_user_id`에 `user.id` 그대로 전달
3. 검색 RPC 호출 시 `p_keyword`에 사용자 입력값 전달
4. 키워드 입력 유형(영문/한글/초성)을 프론트에서 별도로 분기하지 않음
5. 검색 응답(`id`, `name`, `category`, `exercise_type`, `muscle_size`, `primary_muscles`, `secondary_muscles`)으로 자동완성 목록을 구성
6. 히트맵 응답에서 `muscle_code`를 SVG path 키로 사용 (`muscle`은 레거시 호환 필드)
7. 서버 시간 기준(`now()`)으로 색상이 계산되므로 클라이언트에서 시간 계산 금지
8. 기록 저장 시 payload 규칙:
   - 유산소(`exercise_type='cardio'`): `duration_minutes` 필수, `sets/reps/weight_kg`는 `null` 가능
   - 무산소(`exercise_type='weight'`): `sets/reps` 필수, `duration_minutes/distance_km`는 선택
9. 프론트 fallback 문자열(`근육 부위`, `Unknown`) 표시 금지:
   - 항상 API의 `display_name_ko`를 우선 렌더링
   - `display_name_ko` 비어있음/placeholder인 경우를 에러로 기록(정상 플로우에서 0건이어야 함)

---

## 8) Seed 데이터 요약

- 근육 표준 코드: 34개
- 운동 종목: 1073개
- 카테고리: free_weight, machine, bodyweight, cable, band, kettlebell, olympic, strongman, cardio, plyometric
- 메타데이터: `exercise_type(cardio|weight)`, `muscle_size(large|small)` 포함
- 해부학 데이터: `primary_muscles`, `secondary_muscles`, `biomechanics_note` 포함
- 근육 표준 메타: `display_name_ko`, `display_name_latin`, `anatomy_id`, `parent_muscle_code`, `side`
- 매핑: 그룹 기반 주동근/협응근 자동 생성
- 검색 별칭(한글/동의어/약어): 업서트 방식으로 관리 (현재 117건)
