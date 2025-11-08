## 근피로도 측정 App – SQLite 스키마 명세서

### 1. 개요
- **대상**: 모바일 로컬 DB (SQLite 3)
- **기능**: 근피로도 측정 세션의 윈도우 단위 데이터 저장 및 동기화
- **핵심 구성**: 사용자 상태, 윈도우 피쳐 데이터셋, 모델 버전, 동기화 이력

| 테이블 | 역할 |
| ------ | ---- |
| `user_state` | baseline, user embedding, 모델 버전 |
| `fatigue_dataset` | 슬라이딩 윈도우 단위 근피로도 피쳐 |
| `model_versions` | 추론 모델 버전 관리 |
| `sync_history` | 업로드/동기화 이력 |

---

### 2. 테이블 정의

#### 2.1 `user_state`
사용자별 baseline 및 개인화 벡터를 저장합니다.

```sql
CREATE TABLE IF NOT EXISTS user_state (
  user_id TEXT PRIMARY KEY,
  rms_base REAL,
  freq_base REAL,
  user_emb TEXT,             -- JSON 12D vector
  model_version TEXT,
  last_sync TEXT
);
```

#### 2.2 `fatigue_dataset`
요청한 스키마에 맞춰 윈도우 단위 데이터를 저장합니다. SQLite 호환을 위해 `INTEGER PRIMARY KEY AUTOINCREMENT` 구문을 사용합니다. `mode`와 `synced` 컬럼은 동기화 및 UI용 메타데이터입니다.

```sql
CREATE TABLE IF NOT EXISTS fatigue_dataset (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  session_id TEXT,
  window_id INTEGER NOT NULL,
  window_start_ms INTEGER NOT NULL,
  window_end_ms INTEGER NOT NULL,
  timestamp_utc TEXT,
  acc_x_mean REAL,
  acc_y_mean REAL,
  acc_z_mean REAL,
  gyro_x_mean REAL,
  gyro_y_mean REAL,
  gyro_z_mean REAL,
  linacc_x_mean REAL,
  linacc_y_mean REAL,
  linacc_z_mean REAL,
  gravity_x_mean REAL,
  gravity_y_mean REAL,
  gravity_z_mean REAL,
  acc_x_std REAL,
  acc_y_std REAL,
  acc_z_std REAL,
  gyro_x_std REAL,
  gyro_y_std REAL,
  gyro_z_std REAL,
  rms_acc REAL,
  rms_gyro REAL,
  mean_freq_acc REAL,
  mean_freq_gyro REAL,
  entropy_acc REAL,
  entropy_gyro REAL,
  jerk_mean REAL,
  jerk_std REAL,
  stability_index REAL,
  rms_base REAL,
  freq_base REAL,
  user_emb TEXT,
  fatigue_prev REAL,
  fatigue REAL,
  fatigue_level INTEGER,
  quality_flag INTEGER DEFAULT 1,
  window_size_ms INTEGER DEFAULT 2000,
  overlap_rate REAL DEFAULT 0.5,
  mode TEXT,
  synced INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_dataset_user ON fatigue_dataset(user_id);
CREATE INDEX IF NOT EXISTS idx_dataset_session ON fatigue_dataset(session_id);
CREATE INDEX IF NOT EXISTS idx_dataset_synced ON fatigue_dataset(synced);
```

#### 2.3 `model_versions`

```sql
CREATE TABLE IF NOT EXISTS model_versions (
  model_type TEXT PRIMARY KEY,
  version TEXT,
  path TEXT,
  updated_at TEXT NOT NULL
);
```

#### 2.4 `sync_history`

```sql
CREATE TABLE IF NOT EXISTS sync_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  sync_type TEXT NOT NULL,
  status TEXT NOT NULL,
  executed_at TEXT NOT NULL
);
```

---

### 3. 관계 요약
- `user_state (1)` → `fatigue_dataset (N)` : 한 사용자의 모든 윈도우 데이터와 연결
- `user_state (1)` → `sync_history (N)` : 동기화 이력 추적
- `model_versions` : 전역 단일 테이블

---

### 4. 운영 메모
- 기본 사용자 ID: `local_user`
- 윈도우 크기: `SensorConfig.windowSeconds * 1000`
- 오버랩 비율: `1 - hop/window`
- 동기화 여부: `fatigue_dataset.synced`
- 업로드 시에는 세션 단위(`session_id`)로 윈도우를 묶어 전송

---

### 5. 예시 쿼리

최근 7일 동안의 평균 피로도:
```sql
WITH session_summary AS (
  SELECT session_id,
         MIN(window_start_ms) AS first_ms,
         AVG(fatigue) AS avg_fatigue
  FROM fatigue_dataset
  WHERE user_id = 'local_user'
  GROUP BY session_id
)
SELECT AVG(avg_fatigue) AS week_avg
FROM session_summary
WHERE first_ms >= strftime('%s','now','-7 day') * 1000;
```

세션별 윈도우 목록:
```sql
SELECT *
FROM fatigue_dataset
WHERE session_id = :session_id
ORDER BY window_id ASC;
```

동기화되지 않은 세션 식별:
```sql
SELECT session_id, COUNT(*) AS window_count
FROM fatigue_dataset
WHERE synced = 0
GROUP BY session_id;
```

---

### 6. 초기 데이터 시드
```sql
INSERT OR IGNORE INTO user_state (
  user_id, user_emb, model_version, last_sync
) VALUES (
  'local_user',
  json('[0,0,0,0,0,0,0,0,0,0,0,0]'),
  '1.0.0',
  datetime('now')
);
```

---

### 7. 향후 확장 아이디어
- `user_emb` 컬럼을 23ai `VECTOR(12)` 타입으로 추가
- `fatigue_dataset`에 `linacc`/`gravity` 통계 자동 계산
- 서버 측 파이프라인에서 세션 단위 요약 뷰 제공

