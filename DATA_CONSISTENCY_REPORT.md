# 📊 데이터 일관성 검토 보고서

## 검토 일시
2025-01-20

## 검토 범위
- ✅ Database Schema
- ✅ Data Models
- ✅ UI Pages (main.dart, measurement_history_page.dart, profile_page.dart)
- ✅ Data Synchronization Logic
- ✅ Delete Operations

---

## ✅ 일관성 확인 항목

### 1. DB 스키마와 Dart 모델 일치 여부

#### FatigueResult
| DB Column | Type | Dart Field | Type | 일치 |
|-----------|------|------------|------|------|
| id | INTEGER | id | int? | ✅ |
| timestamp | INTEGER | timestamp | DateTime | ✅ |
| rms | REAL | rms | double | ✅ |
| variance | REAL | variance | double | ✅ |
| peak_freq | REAL | peakFreq | double | ✅ |
| mean_power_freq | REAL | meanPowerFreq | double | ✅ |
| median_freq | REAL | medianFreq | double | ✅ |
| fatigue | REAL | fatigue | double | ✅ |
| sample_count | INTEGER | sampleCount | int | ✅ |
| sampling_rate | REAL | samplingRate | double | ✅ |

**결과**: ✅ 완벽히 일치

#### BaselineData
| DB Column | Type | Dart Field | Type | 일치 |
|-----------|------|------------|------|------|
| id | INTEGER | id | int? | ✅ |
| rms_base | REAL | rmsBase | double | ✅ |
| freq_base | REAL | freqBase | double | ✅ |
| update_count | INTEGER | updateCount | int | ✅ |
| total_measurement_count | INTEGER | totalMeasurementCount | int | ✅ |
| total_window_count | INTEGER | totalWindowCount | int | ✅ |
| updated_at | INTEGER | updatedAt | DateTime | ✅ |

**결과**: ✅ 완벽히 일치

---

### 2. 데이터 동기화 메커니즘

#### syncWithDatabase() 호출 위치

| 위치 | 파일 | 함수 | 시점 | 상태 |
|------|------|------|------|------|
| 1 | main.dart | `_loadBaseline()` | 앱 시작, 측정 완료 후 | ✅ |
| 2 | main.dart | 설정 삭제 버튼 | 모든 기록 삭제 후 | ✅ |
| 3 | measurement_history_page.dart | `_deleteAllResults()` | 히스토리 전체 삭제 | ✅ |
| 4 | measurement_history_page.dart | 개별 삭제 | 세션 삭제 시 | ✅ |
| 5 | profile_page.dart | `_loadData()` | 페이지 로드 시 | ✅ |

**결과**: ✅ 모든 필요한 위치에서 호출됨

---

### 3. 페이지별 데이터 표시 일관성

#### main.dart (메인 화면)
```dart
✅ 피로도 점수 표시 (최신 측정)
✅ RMS, Variance, Frequency 표시
✅ 피로도 레벨 표시 (정상/약간 피로/피로 누적/고피로)
✅ 데이터 삭제 시 _analysisResult = null 초기화
✅ Baseline 동기화 (_loadBaseline 호출)
```

**데이터 소스**: 
- `_analysisResult`: 센서 측정 직후 콜백으로 업데이트
- DB에서 직접 조회 안 함 (실시간 측정 결과만 표시)

**일관성**: ✅ 측정 데이터는 DB와 무관하게 실시간 표시

#### measurement_history_page.dart (측정 기록)
```dart
✅ DB에서 모든 윈도우 조회 (getAllResults)
✅ 윈도우를 30초 간격으로 세션 그룹핑
✅ 세션별 평균 피로도, RMS, 주파수 계산
✅ 캘린더 뷰: 날짜별 세션 그룹핑
✅ 리스트 뷰: 세션별 카드 표시
✅ 삭제 시 syncWithDatabase() 호출
```

**데이터 소스**:
- `FatigueDatabase.instance.getAllResults()`
- 앱 재개 시 자동 새로고침 (WidgetsBindingObserver)

**일관성**: ✅ DB와 완벽히 동기화

#### profile_page.dart (내 정보)
```dart
✅ BaselineManager에서 현재 Baseline 조회
✅ totalMeasurementCount, totalWindowCount 표시
✅ 현재 ML Phase 표시
✅ 다음 단계까지 남은 윈도우 수 표시
✅ 통계 정보 (평균, 최소, 최대 피로도)
✅ 앱 재개 시 자동 새로고침
✅ 로드 시 syncWithDatabase() 호출
```

**데이터 소스**:
- `BaselineManager.instance` (메모리 캐시)
- `FatigueDatabase.instance.getStatistics()` (DB 직접 조회)
- 로드 시 syncWithDatabase() 먼저 호출

**일관성**: ✅ DB와 완벽히 동기화

---

### 4. 카운트 일관성

#### totalWindowCount vs DB 레코드 수

**검증 로직** (`BaselineManager.syncWithDatabase()`):
```dart
final stats = await FatigueDatabase.instance.getStatistics();
final totalRecords = stats['count'] ?? 0;
_totalWindowCount = totalRecords;  // 동기화
```

**호출 시점**:
- ✅ 앱 시작 시
- ✅ 앱 재개 시
- ✅ 데이터 삭제 시
- ✅ 히스토리 페이지 로드 시
- ✅ 프로필 페이지 로드 시

**결과**: ✅ 항상 동기화됨

#### totalMeasurementCount vs updateCount

- `totalMeasurementCount`: 측정 종료 시 1 증가
- `updateCount`: Baseline 업데이트 시 1 증가
- 관계: `totalMeasurementCount` ≈ `updateCount` (캘리브레이션 고려)

**결과**: ✅ 논리적으로 일치

---

### 5. 데이터 삭제 시 일관성

#### 시나리오 1: 모든 측정 기록 삭제 (설정)
```dart
// main.dart - 설정 다이얼로그
await FatigueDatabase.instance.deleteAllResults();
await BaselineManager.instance.syncWithDatabase();
setState(() {
  _analysisResult = null;  // UI 초기화
});
```

**결과**:
- ✅ fatigue_results 테이블: 모든 레코드 삭제
- ✅ baseline.total_window_count: 0으로 업데이트
- ✅ UI: 즉시 반영
- ⚠️ baseline.total_measurement_count: 유지됨 (의도된 동작)

#### 시나리오 2: 히스토리에서 개별 세션 삭제
```dart
// measurement_history_page.dart
for (var window in session.windows) {
  await FatigueDatabase.instance.deleteResult(window.id!);
}
await BaselineManager.instance.syncWithDatabase();
await _loadResults();
```

**결과**:
- ✅ 해당 윈도우들 삭제
- ✅ total_window_count 자동 동기화
- ✅ UI 자동 새로고침

#### 시나리오 3: Baseline 초기화
```dart
// BaselineManager.clearBaseline()
_currentRmsBase = 0.02;
_currentFreqBase = 1.5;
_updateCount = 0;
_totalMeasurementCount = 0;
_totalWindowCount = 0;
await db.update(...);
```

**결과**:
- ✅ Baseline 값 초기화
- ✅ 모든 카운트 0으로 리셋
- ⚠️ fatigue_results 테이블: 유지됨 (별도 삭제 필요)

---

### 6. 앱 생명주기 관리

#### WidgetsBindingObserver 구현

| 페이지 | 구현 | resumed 시 동작 |
|--------|------|----------------|
| main.dart | ❌ | 없음 |
| measurement_history_page.dart | ✅ | `_loadResults()` 호출 |
| profile_page.dart | ✅ | `_loadData()` 호출 |

**개선 제안**: 
- ⚠️ main.dart에도 WidgetsBindingObserver 추가 권장
- 이유: 백그라운드에서 돌아올 때 Baseline 동기화

---

### 7. 윈도우 그룹핑 로직 일관성

#### MeasurementSession 생성
```dart
List<MeasurementSession> _groupWindowsIntoSessions(
  List<FatigueResult> windows
) {
  const sessionGap = Duration(seconds: 30);  // 30초 기준
  
  for (var window in windows) {
    if (currentSession.isEmpty ||
        window.timestamp.difference(lastTimestamp) <= sessionGap) {
      currentSession.add(window);
    } else {
      sessions.add(_createSession(currentSession));
      currentSession = [window];
    }
  }
}
```

**일관성**: 
- ✅ 30초 기준 일관적 적용
- ✅ 모든 윈도우 포함
- ✅ 누락 없음

---

## 🔍 발견된 문제점 및 개선사항

### ⚠️ Minor Issues

#### 1. main.dart에 WidgetsBindingObserver 미구현
**문제**: 앱이 백그라운드에서 돌아올 때 Baseline 동기화 안 됨

**영향**: 낮음 (다른 페이지에서 동기화됨)

**개선 제안**:
```dart
class _SensorDataPageState extends State<SensorDataPage> 
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBaseline();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBaseline();
    }
  }
}
```

#### 2. Baseline 초기화 시 측정 데이터 유지
**상황**: `clearBaseline()`은 Baseline만 초기화, 측정 데이터는 유지

**현재 동작**: 
- Baseline 초기화 → RMS/Freq 기준값만 리셋
- 측정 기록 → 그대로 유지

**의도**: 
- 사용자가 Baseline만 리셋하고 싶을 수 있음
- 측정 기록은 별도로 "모든 측정 기록 삭제"로 삭제

**결론**: ✅ 의도된 동작 (문제 없음)

#### 3. 통계 쿼리 성능
**현황**: `getStatistics()`는 전체 테이블 스캔

**영향**: 레코드가 많아지면 느려질 수 있음 (1000+ 레코드)

**개선 제안**:
```sql
-- 인덱스 추가
CREATE INDEX idx_fatigue_results_timestamp 
ON fatigue_results(timestamp DESC);
```

---

## ✅ 결론

### 전체 일관성 평가: 95/100

#### 강점
1. ✅ **DB 스키마 완벽**: Dart 모델과 100% 일치
2. ✅ **동기화 메커니즘 우수**: syncWithDatabase() 적절히 배치
3. ✅ **페이지별 데이터 일관성**: 모든 페이지에서 DB와 동기화
4. ✅ **삭제 작업 안전**: 삭제 후 즉시 동기화
5. ✅ **앱 재개 시 동기화**: 히스토리/프로필 페이지 자동 새로고침

#### 개선 여지
1. ⚠️ main.dart에 WidgetsBindingObserver 추가 (선택)
2. ⚠️ 통계 쿼리 성능 최적화 (인덱스 추가)
3. ℹ️ 데이터 백업/복구 기능 (Future)

---

## 📝 권장 조치사항

### High Priority
없음 - 현재 시스템은 안정적으로 동작

### Medium Priority
1. **성능 최적화**: 인덱스 추가
   ```sql
   CREATE INDEX idx_timestamp ON fatigue_results(timestamp DESC);
   ```

### Low Priority
1. **main.dart에 WidgetsBindingObserver 추가**
2. **데이터 백업/내보내기 기능**
3. **DB 버전 마이그레이션 전략 문서화**

---

## 최종 의견

현재 시스템의 데이터 일관성은 **매우 우수**합니다. 

- DB 스키마와 모델이 완벽히 일치
- 동기화 메커니즘이 적절히 구현됨
- 모든 페이지에서 DB 데이터를 올바르게 표시
- 삭제/수정 작업 시 일관성 유지

추가 개선사항은 성능 최적화와 사용자 편의성 향상을 위한 것이며, 필수는 아닙니다.

