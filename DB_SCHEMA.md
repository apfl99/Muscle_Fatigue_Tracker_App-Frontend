좋아요 👍 완벽하게 현실적인 방향이에요.
“7일 누적 데이터가 쌓여야 개인화가 시작되는 구조”는 실제 초반 사용자에게 너무 느립니다.
따라서 **초기 사용자도 바로 개인화(user_emb 계산)** 가 가능하도록,
👉 “누적 일수에 관계없이 최근 N회(예: 3~5회) 측정 데이터”만으로 동작하도록 바꾸면 됩니다.

아래는 이 변경을 반영한 **최신 설계 버전 (SQLite 스키마 + 로직 포함)** Markdown 파일이에요.

---

````markdown
# 🧱 근피로도 측정 App – Local SQLite Database Schema (v1.4)
**Last Updated:** 2025-10-20  
**Author:** 근피로도 측정 앱 개발팀  

---

## 📘 개요

이 버전은 기존 “최근 7일 통계 기반 사용자 임베딩(user_emb)” 방식을 개선하여,  
데이터가 적은 초기 사용자도 **최근 N회(기본 5회)** 측정 기록만으로 개인화가 가능하도록 설계되었다.  

즉, **데이터가 쌓일수록 자동으로 7일 평균 기반으로 전환**,  
데이터가 적을 땐 **최근 기록 기반으로 유연하게 계산**한다.

---

## 📂 테이블 요약

| 구분 | 테이블명 | 역할 |
|------|-----------|------|
| 🧍‍♂️ 사용자 기준 | `baseline` | 개인별 EMA 기준값 저장 |
| 📊 사용자 통계 | `user_stats` | 최근 N회(≤7일) 통계 기반 user embedding 계산용 |
| ⚡ 측정 세션 | `measure_sessions` | 5초 단위 측정 결과 (UI 및 baseline 갱신용) |
| 🔁 윈도우 캐시 | `window_features` | 0.5초 hop 윈도우 단위 feature 저장 (ML용) |

---

## 🧍‍♂️ baseline

> EMA 기반 RMS/Freq 기준을 저장한다.  
> 데이터가 쌓이지 않아도 baseline은 즉시 생성 가능하다.

```sql
CREATE TABLE IF NOT EXISTS baseline (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    rms_base REAL NOT NULL,
    freq_base REAL NOT NULL,
    alpha REAL DEFAULT 0.05,
    beta REAL DEFAULT 0.05,
    updated_at TEXT NOT NULL
);
````

---

## 📊 user_stats (개선된 사용자 통계)

> 기존 “7일 누적” 대신 “최근 N회(기본 5회)” 측정 기록만을 기반으로
> **user_emb** 계산이 가능하도록 변경.

```sql
CREATE TABLE IF NOT EXISTS user_stats (
    sample_window INTEGER DEFAULT 5,   -- 최근 N회 사용 기준
    meas_count INTEGER,                -- 사용자가 실제 측정한 횟수
    rms_mean REAL,
    freq_mean REAL,
    rms_var REAL,
    freq_var REAL,
    fatigue_mean REAL,
    fatigue_cv REAL,
    drift_rms REAL,
    drift_freq REAL,
    time_of_day_mean REAL,
    session_len_mean REAL,
    updated_at TEXT
);
```

### 계산 로직

* **데이터가 5회 미만**이면 → 지금까지 기록된 모든 데이터 사용
* **데이터가 5회 이상**이면 → 최근 5회(`ORDER BY timestamp DESC LIMIT 5`) 기준 계산
* **7일 이상** 누적 시 → `WHERE timestamp >= DATE('now','-7 days')` 로 자동 전환 가능

```sql
-- 최근 N회(기본 5회) 기준 통계 계산 예시
SELECT 
  COUNT(*) AS meas_count,
  AVG(rms) AS rms_mean,
  VARIANCE(rms) AS rms_var,
  AVG(freq) AS freq_mean,
  VARIANCE(freq) AS freq_var,
  AVG(fatigue) AS fatigue_mean,
  (STDDEV(fatigue)/AVG(fatigue)) AS fatigue_cv
FROM (
  SELECT rms, freq, fatigue 
  FROM measure_sessions 
  ORDER BY timestamp DESC LIMIT 5
);
```

이 통계 결과를 `baseline` 의 `rms_base`, `freq_base` 와 결합하여
**즉시 user_emb(12D)** 생성 가능.

---

## ⚡ measure_sessions

```sql
CREATE TABLE IF NOT EXISTS measure_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    rms REAL,
    freq REAL,
    fatigue REAL,
    mode TEXT,
    window_count INTEGER,
    signal_path TEXT,
    synced INTEGER DEFAULT 0
);
```

> 앱이 시작된 첫날부터 측정 1회만 있어도 baseline과 user_emb 계산 가능.
> `window_count`는 Hybrid/End-to-End 전환 조건 판단에 사용된다.

---

## 🔁 window_features

```sql
CREATE TABLE IF NOT EXISTS window_features (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    window_index INTEGER NOT NULL,
    rms REAL NOT NULL,
    freq REAL NOT NULL,
    fatigue_prev REAL,
    fatigue_pred REAL,
    label REAL,
    FOREIGN KEY(session_id) REFERENCES measure_sessions(id)
);
```

> ML 모델(1D-CNN+GRU) 학습용 캐시.
> 5초 측정당 약 9~10개의 윈도우 피처가 생성된다.

---

## 🧮 사용자 임베딩(user_emb) 생성 로직 (동적 윈도우 기반)

| Feature Index | Feature            | 계산 방식                 |
| ------------- | ------------------ | --------------------- |
| 0             | `rms_base`         | baseline 테이블          |
| 1             | `freq_base`        | baseline 테이블          |
| 2             | `rms_var`          | 최근 N회 RMS 분산          |
| 3             | `freq_var`         | 최근 N회 Freq 분산         |
| 4             | `meas_count`       | 최근 N회 측정 수            |
| 5             | `fatigue_mean`     | 최근 N회 평균 피로도          |
| 6             | `fatigue_cv`       | 최근 N회 피로도 변동계수        |
| 7             | `drift_rms`        | RMS 변화량 (최근 vs 이전 평균) |
| 8             | `drift_freq`       | Freq 변화량              |
| 9             | `time_of_day_mean` | 최근 사용 시간대 평균          |
| 10            | `session_len_mean` | 최근 세션 길이(초)           |
| 11            | `sample_window`    | 현재 통계 샘플 개수           |

📘 **→ 모든 feature는 최근 데이터만으로도 계산 가능하며,**
데이터가 늘어나면 자동으로 더 정밀해진다.

---

## ⚙️ 데이터 유지 정책

| 데이터                      | 유지기간     | 관리 방식       |
| ------------------------ | -------- | ----------- |
| `measure_sessions`       | 무제한      | 핵심 측정 로그    |
| `window_features`        | 최근 14일   | 자동 삭제       |
| `signal_path` 내 파일       | 최근 14일   | 자동 삭제       |
| `baseline`, `user_stats` | 항상 최신 1행 | 매 갱신 시 덮어쓰기 |

---

## 🔧 동기화 정책

* 앱 idle 시 1일 1회 `/upload_logs` 호출
* 전송 데이터: `measure_sessions` + `user_stats`
* 전송 후 `synced=1`
* 서버에서 사용자별 fine-tuning 가능

---

## 💾 예시 쿼리

### ① 최근 N회 통계 갱신

```sql
INSERT OR REPLACE INTO user_stats
SELECT
  5 AS sample_window,
  COUNT(*) AS meas_count,
  AVG(rms) AS rms_mean,
  AVG(freq) AS freq_mean,
  VARIANCE(rms) AS rms_var,
  VARIANCE(freq) AS freq_var,
  AVG(fatigue) AS fatigue_mean,
  (STDDEV(fatigue)/AVG(fatigue)) AS fatigue_cv,
  (AVG(rms) - (SELECT rms_base FROM baseline)) AS drift_rms,
  (AVG(freq) - (SELECT freq_base FROM baseline)) AS drift_freq,
  (AVG(STRFTIME('%H', timestamp))/24.0) AS time_of_day_mean,
  (AVG(window_count)/10.0) AS session_len_mean,
  DATETIME('now') AS updated_at
FROM (
  SELECT * FROM measure_sessions ORDER BY timestamp DESC LIMIT 5
);
```

### ② user_emb 구성용 Python 예시

```python
user_emb = [
  rms_base, freq_base,
  stats['rms_var'], stats['freq_var'],
  stats['meas_count'], stats['fatigue_mean'], stats['fatigue_cv'],
  stats['drift_rms'], stats['drift_freq'],
  stats['time_of_day_mean'], stats['session_len_mean'],
  stats['sample_window']
]
```

---

## ✅ 요약

| 테이블                | 역할          | 특징                |
| ------------------ | ----------- | ----------------- |
| `baseline`         | EMA 기준 저장   | 1행 고정             |
| `user_stats`       | 최근 N회 통계 기반 | 데이터 적어도 즉시 개인화 가능 |
| `measure_sessions` | 5초 세션 로그    | baseline 갱신 및 UI용 |
| `window_features`  | 윈도우 캐시      | ML 학습용            |

---

## 💡 개선 포인트

* ✅ **초기 사용자도 즉시 개인화 가능** (N=3~5회 데이터만으로)
* ✅ **데이터 많을수록 자동으로 장기 통계 반영**
* ✅ **온디바이스 연산량 최소화** (최근 세션만 통계)
* ✅ **서버 동기화/재학습 구조 동일 유지**

---

> ⚡ 본 설계는 EMA → Hybrid → End-to-End ML 단계별 전환을 지원하면서
> “데이터가 적은 초기 사용자”부터 **개인화된 피로도 추정이 가능하도록** 설계된
> Muscle Fatigue Tracker App의 최신 SQLite 스키마이다.
