좋아요 👏
아래는 **근피로도 측정 App의 데이터베이스 스키마 명세서(개발자용)** 로,
실제 **Oracle Autonomous Database (23ai 기준)** 및 **SQLite (모바일 앱용)** 에서 바로 구축 가능한 형태로 작성한 것입니다.

이 문서는 **ERD 구조 + DDL + 컬럼 설명 + 인덱스/관계/저장 방식**까지 포함되어 있어
백엔드/DBA/ML/모바일 개발자가 바로 참고할 수 있습니다.

---

# 🧱 근피로도 측정 App – Database 스키마 명세서

**Version:** `v1.0.0`
**DB Engine:** 
- Oracle Autonomous Database (23ai) - 서버용
- SQLite 3 - 모바일 앱용 (로컬)

**작성 대상:** Backend Developer / DBA / ML Engineer / Mobile Developer

---

## 1️⃣ 스키마 개요

본 데이터베이스는 **사용자 상태(baseline, user_emb), 측정 로그, 모델 버전 관리**를 담당하며
ML 파이프라인의 Hybrid / End-to-End 학습에 필요한 피로도 데이터셋을 보존한다.

| 주요 테이블           | 설명                        |
| ---------------- | ------------------------- |
| `users`          | 사용자 계정 정보                 |
| `user_state`     | 개인별 baseline, user_emb 상태 |
| `fatigue_logs`   | 피로도 측정 이력                 |
| `model_versions` | 서버 및 앱 사용 모델 버전 관리        |
| `sync_history`   | 동기화 이벤트 기록                |

---

## 2️⃣ ERD 구조

```
 ┌──────────────┐        ┌──────────────┐
 │   users      │1      ∞│  user_state  │
 │──────────────│        │──────────────│
 │ id (PK)      │◄──────┤ user_id (FK) │
 │ email        │        │ rms_base     │
 │ created_at   │        │ freq_base    │
 └──────────────┘        │ user_emb     │
                         │ model_version│
                         │ last_sync    │
                         └──────────────┘
                                │
                                │1
                                ▼∞
                         ┌──────────────┐
                         │fatigue_logs  │
                         │──────────────│
                         │ user_id (FK) │
                         │ fatigue      │
                         │ mode         │
                         └──────────────┘
```

---

## 3️⃣ 테이블 정의

---

### 🧩 Table: `users`

| 컬럼명             | 타입              | 제약조건                 | 설명        |
| --------------- | --------------- | -------------------- | --------- |
| `id`            | `VARCHAR2(36)`  | PRIMARY KEY          | 사용자 UUID  |
| `email`         | `VARCHAR2(255)` | UNIQUE, NOT NULL     | 로그인 이메일   |
| `password_hash` | `VARCHAR2(255)` | NOT NULL             | 암호화된 비밀번호 |
| `created_at`    | `TIMESTAMP`     | DEFAULT SYSTIMESTAMP | 계정 생성 일시  |

#### 📘 DDL

```sql
CREATE TABLE users (
  id VARCHAR2(36) PRIMARY KEY,
  email VARCHAR2(255) UNIQUE NOT NULL,
  password_hash VARCHAR2(255) NOT NULL,
  created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

---

### 🧩 Table: `user_state`

| 컬럼명             | 타입              | 제약조건                   | 설명                   |
| --------------- | --------------- | ---------------------- | -------------------- |
| `user_id`       | `VARCHAR2(36)`  | FK(users.id), NOT NULL | 사용자 ID               |
| `rms_base`      | `FLOAT`         |                        | EMA 기반 RMS 기준값       |
| `freq_base`     | `FLOAT`         |                        | EMA 기반 Frequency 기준값 |
| `user_emb`      | `CLOB` *(JSON)* |                        | 사용자 임베딩 벡터(12D)      |
| `model_version` | `VARCHAR2(20)`  |                        | 현재 적용 모델 버전          |
| `last_sync`     | `TIMESTAMP`     | DEFAULT SYSTIMESTAMP   | 최근 동기화 시각            |

#### 📘 DDL

```sql
CREATE TABLE user_state (
  user_id VARCHAR2(36) REFERENCES users(id),
  rms_base FLOAT,
  freq_base FLOAT,
  user_emb CLOB,
  model_version VARCHAR2(20),
  last_sync TIMESTAMP DEFAULT SYSTIMESTAMP,
  CONSTRAINT user_state_pk PRIMARY KEY (user_id)
);
```

#### 📗 향후 23ai VECTOR 타입 확장 예시

```sql
ALTER TABLE user_state ADD user_emb_vec VECTOR(12);
```

> `user_emb_vec` 컬럼은 23ai 환경에서 Vector Search를 활성화할 때 사용 가능.

---

### 🧩 Table: `fatigue_logs`

| 컬럼명            | 타입             | 제약조건                 | 설명                 |
| -------------- | -------------- | -------------------- | ------------------ |
| `user_id`      | `VARCHAR2(36)` | FK(users.id)         | 사용자 식별자            |
| `session_id`   | `VARCHAR2(64)` | PRIMARY KEY          | 세션 고유 ID           |
| `measure_date` | `DATE`         | DEFAULT SYSDATE      | 측정 일자              |
| `rms`          | `FLOAT`        |                      | 세션 평균 RMS          |
| `freq`         | `FLOAT`        |                      | 세션 평균 Freq         |
| `fatigue`      | `FLOAT`        |                      | 예측된 피로도            |
| `mode`         | `VARCHAR2(20)` |                      | EMA / Hybrid / E2E |
| `window_count` | `NUMBER`       |                      | 윈도우 개수             |
| `created_at`   | `TIMESTAMP`    | DEFAULT SYSTIMESTAMP | 생성 시각              |

#### 📘 DDL

```sql
CREATE TABLE fatigue_logs (
  user_id VARCHAR2(36) REFERENCES users(id),
  session_id VARCHAR2(64) PRIMARY KEY,
  measure_date DATE DEFAULT SYSDATE,
  rms FLOAT,
  freq FLOAT,
  fatigue FLOAT,
  mode VARCHAR2(20),
  window_count NUMBER,
  created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

#### 📊 인덱스

```sql
CREATE INDEX idx_logs_user ON fatigue_logs(user_id);
CREATE INDEX idx_logs_date ON fatigue_logs(measure_date);
```

---

### 🧩 Table: `model_versions`

| 컬럼명          | 타입              | 제약조건                 | 설명                           |
| ------------ | --------------- | -------------------- | ---------------------------- |
| `model_type` | `VARCHAR2(20)`  | PRIMARY KEY          | Hybrid / E2E 구분              |
| `version`    | `VARCHAR2(20)`  |                      | 모델 버전 문자열                    |
| `path`       | `VARCHAR2(255)` |                      | 모델 저장 경로 (Hugging Face Repo) |
| `updated_at` | `TIMESTAMP`     | DEFAULT SYSTIMESTAMP | 버전 업데이트 시각                   |

#### 📘 DDL

```sql
CREATE TABLE model_versions (
  model_type VARCHAR2(20) PRIMARY KEY,
  version VARCHAR2(20),
  path VARCHAR2(255),
  updated_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

---

### 🧩 Table: `sync_history`

| 컬럼명           | 타입             | 제약조건                 | 설명                                          |
| ------------- | -------------- | -------------------- | ------------------------------------------- |
| `user_id`     | `VARCHAR2(36)` | FK(users.id)         | 사용자 식별자                                     |
| `sync_type`   | `VARCHAR2(30)` |                      | upload_state / download_state / upload_logs |
| `status`      | `VARCHAR2(10)` |                      | 성공 / 실패                                     |
| `executed_at` | `TIMESTAMP`    | DEFAULT SYSTIMESTAMP | 수행 시각                                       |

#### 📘 DDL

```sql
CREATE TABLE sync_history (
  user_id VARCHAR2(36) REFERENCES users(id),
  sync_type VARCHAR2(30),
  status VARCHAR2(10),
  executed_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

---

## 4️⃣ 관계 요약

| 관계                               | 설명                    |
| -------------------------------- | --------------------- |
| `users (1)` → `user_state (1)`   | 사용자-상태 일대일 관계         |
| `users (1)` → `fatigue_logs (N)` | 사용자-로그 일대다 관계         |
| `users (1)` → `sync_history (N)` | 사용자-동기화 이벤트 일대다       |
| `model_versions`                 | 전역 단일 테이블 (모델 버전 관리용) |

---

## 5️⃣ 저장 및 관리 정책

| 항목                           | 정책                               | 설명                         |
| ---------------------------- | -------------------------------- | -------------------------- |
| **백업 주기**                    | 월 1회                             | Object Storage에 JSON.gz 백업 |
| **데이터 보존 기간**                | 6개월                              | 6개월 이전 로그는 별도 압축 후 삭제      |
| **Object Storage 경로**        | `logs/YYYYMMDD/user_id.json`     | 세션 로그 파일                   |
| **Vector Search 인덱스 (23ai)** | user_emb_vec                     | 개인 유사도 탐색용                 |
| **DB 접근 권한**                 | `READONLY_USER`, `APP_ADMIN` 2계층 | 읽기/쓰기 분리                   |

---

## 6️⃣ 예시 쿼리

### ✅ 최근 7일 평균 피로도

```sql
SELECT user_id, AVG(fatigue) AS avg_fatigue
FROM fatigue_logs
WHERE measure_date >= SYSDATE - 7
GROUP BY user_id;
```

### ✅ 사용자별 최신 baseline 조회

```sql
SELECT u.email, s.rms_base, s.freq_base, s.model_version
FROM users u
JOIN user_state s ON u.id = s.user_id;
```

### ✅ 특정 사용자 로그 Export

```sql
SELECT JSON_OBJECT(
  'rms' VALUE rms,
  'freq' VALUE freq,
  'fatigue' VALUE fatigue,
  'mode' VALUE mode,
  'date' VALUE measure_date
) AS log_json
FROM fatigue_logs
WHERE user_id = :user_id;
```

---

## 7️⃣ 개발 참고 사항

| 항목               | 권장 설정                     | 설명                      |
| ---------------- | ------------------------- | ----------------------- |
| DB Character Set | `AL32UTF8`                | 다국어 지원                  |
| Storage          | 20GB (Free Tier)          | 충분한 로그 저장               |
| Connection       | Oracle Wallet (JDBC/REST) | HF Space ↔ Oracle 연결    |
| 인증               | JWT 기반 App Token          | `/upload_state` 호출 시 검증 |
| AI 기능 확장 (23ai)  | `VECTOR(12)` 활성화          | user_emb 검색 최적화         |

---

## 8️⃣ SQLite 스키마 (모바일 앱용)

모바일 앱에서는 로컬 SQLite 데이터베이스를 사용하며, 5회 측정마다 데이터를 DB에 저장합니다.

### 📱 주요 특징

- **로컬 우선**: UI는 로컬 데이터를 사용하여 빠른 응답 제공
- **배치 저장**: 5회 측정마다 DB에 저장하여 성능 최적화
- **동기화 지원**: 서버와의 동기화를 위한 synced 플래그
- **단일 사용자**: 로컬 디바이스에서는 단일 사용자 `local_user` 사용

### 📘 테이블 구조

#### 1. users (사용자 정보)
```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT,
  created_at TEXT NOT NULL
);
```

#### 2. user_state (사용자 상태 - baseline + embedding)
```sql
CREATE TABLE user_state (
  user_id TEXT PRIMARY KEY,
  rms_base REAL,
  freq_base REAL,
  user_emb TEXT,           -- JSON 형식 12D 벡터
  model_version TEXT,
  last_sync TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id)
);
```

#### 3. fatigue_logs (피로도 측정 로그)
```sql
CREATE TABLE fatigue_logs (
  user_id TEXT NOT NULL,
  session_id TEXT PRIMARY KEY,
  measure_date TEXT NOT NULL,    -- DATE only (YYYY-MM-DD)
  rms REAL,
  freq REAL,
  fatigue REAL,
  mode TEXT,                      -- EMA / Hybrid / E2E
  window_count INTEGER,
  created_at TEXT NOT NULL,
  synced INTEGER DEFAULT 0,       -- 0: 미동기화, 1: 동기화 완료
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX idx_logs_user ON fatigue_logs(user_id);
CREATE INDEX idx_logs_date ON fatigue_logs(measure_date);
```

#### 4. model_versions (모델 버전 관리)
```sql
CREATE TABLE model_versions (
  model_type TEXT PRIMARY KEY,    -- EMA / Hybrid / E2E
  version TEXT,
  path TEXT,
  updated_at TEXT NOT NULL
);
```

#### 5. sync_history (동기화 이력)
```sql
CREATE TABLE sync_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  sync_type TEXT NOT NULL,        -- upload_state / download_state / upload_logs
  status TEXT NOT NULL,            -- success / failure
  executed_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);
```

#### 6. temp_measurements (임시 측정 데이터)
```sql
CREATE TABLE temp_measurements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  window_index INTEGER NOT NULL,
  rms REAL NOT NULL,
  freq REAL NOT NULL,
  fatigue REAL,
  timestamp TEXT NOT NULL
);
```
> **용도**: UI에서 사용하는 임시 데이터. 5회 측정이 완료되면 `fatigue_logs`로 이동하고 삭제됨.

### 🔄 데이터 흐름

```
1. 측정 시작
   └─> temp_measurements에 윈도우별 데이터 삽입

2. 측정 완료 (5회마다)
   └─> temp_measurements 집계
   └─> fatigue_logs에 평균값 저장 (synced=0)
   └─> temp_measurements 삭제
   └─> user_state의 baseline 업데이트 (EMA)

3. 서버 동기화 (주기적)
   └─> 미동기화 로그 조회 (synced=0)
   └─> 서버로 업로드
   └─> synced=1로 업데이트
   └─> sync_history에 기록
```

### 🛠️ 주요 메서드

| 메서드 | 설명 |
|-------|------|
| `insertTempMeasurement()` | 임시 측정 데이터 삽입 |
| `commitTempMeasurementsToLogs()` | 5회 측정 완료 시 DB에 커밋 |
| `getUnsyncedLogs()` | 서버 동기화가 필요한 로그 조회 |
| `markLogsAsSynced()` | 동기화 완료 표시 |
| `recalculateBaseline()` | 최근 N회 기준 baseline 재계산 |
| `getUserEmbedding()` | 사용자 임베딩 벡터 조회 |

---

## ✅ 결론

> 본 스키마는 **근피로도 측정 App의 ML 추론 및 데이터 동기화 파이프라인**을
> Oracle Autonomous Database(23ai)와 SQLite(모바일)에서 운용하기 위한 표준 데이터베이스 구조이다.

핵심 특징:

* 개인별 baseline/user_emb 저장
* 세션별 피로도 로그 추적
* 모델 버전 및 동기화 관리
* 벡터 기반 개인화 확장(23ai Vector Search 지원)
* **모바일**: 로컬 우선 + 5회 배치 저장 + 서버 동기화

---
