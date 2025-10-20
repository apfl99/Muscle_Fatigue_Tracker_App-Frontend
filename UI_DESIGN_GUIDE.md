# 🎨 UI Design Guide

## 디자인 컨셉

[Fitness Health Tracker Mobile App UI](https://kr.pinterest.com/pin/1145532855445326431/)을 참고한 모던 피트니스 앱 디자인

### 주요 특징
- 🟢 **녹색/검은색 컬러 스킴**: 건강과 활력을 나타내는 녹색 + 모던한 다크 배경
- 💪 **피트니스 앱 감성**: 운동/건강 앱 느낌의 아이콘과 그라데이션
- 📱 **일관된 디자인 시스템**: 모든 화면에서 통일된 컴포넌트 스타일
- ✨ **모던 카드 디자인**: 그림자, 그라데이션, 둥근 모서리

---

## 컬러 팔레트

### 메인 컬러
```dart
primaryGreen   = #00E676  // 메인 녹색 (버튼, 강조)
darkGreen      = #00C853  // 어두운 녹색 (그라데이션)
accentGreen    = #69F0AE  // 연한 녹색 (액센트)
```

### 배경 컬러
```dart
darkBackground = #0A0E27  // 메인 배경 (진한 남색/검정)
cardBackground = #1C1F3A  // 카드 배경
cardDark       = #161932  // 카드 어두운 부분
```

### 피로도 레벨 컬러
```dart
정상      = #00E676  (녹색)
약간 피로 = #FFEB3B  (노란색)
피로 누적 = #FF9800  (오렌지)
고피로    = #E53935  (빨간색)
```

### ML Phase 컬러
```dart
Phase 1 (EMA)        = #2196F3  (파란색)
Phase 2 (Hybrid)     = #AB47BC  (보라색)
Phase 3 (End-to-End) = #7B1FA2  (진보라색)
```

---

## 주요 컴포넌트

### 1. 카드 스타일

#### 기본 카드
```dart
Container(
  decoration: AppTheme.cardDecoration(),
  padding: EdgeInsets.all(24),
  child: ...
)
```

#### 그라데이션 카드
```dart
Container(
  decoration: AppTheme.cardDecoration(
    gradient: AppTheme.primaryGradient,
  ),
  padding: EdgeInsets.all(24),
  child: ...
)
```

#### 피로도 카드
```dart
Container(
  decoration: AppTheme.cardDecoration(
    gradient: AppTheme.fatigueGradient(fatigueScore),
  ),
  padding: EdgeInsets.all(24),
  child: ...
)
```

### 2. 버튼 스타일

#### 메인 액션 버튼
```dart
Container(
  decoration: AppTheme.cardDecoration(
    gradient: AppTheme.primaryGradient,
    borderRadius: 16,
  ),
  child: Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: ...
    ),
  ),
)
```

#### 아이콘 버튼
```dart
Container(
  padding: EdgeInsets.all(8),
  decoration: AppTheme.iconButtonDecoration(),
  child: Icon(icon, color: AppTheme.primaryGreen),
)
```

### 3. 텍스트 스타일

#### 헤드라인
```dart
TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.bold,
  color: Colors.white,
)
```

#### 타이틀
```dart
TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: Colors.white,
)
```

#### 본문
```dart
TextStyle(
  fontSize: 14,
  color: Colors.white.withOpacity(0.7),
)
```

#### 캡션
```dart
TextStyle(
  fontSize: 12,
  color: Colors.white.withOpacity(0.5),
)
```

---

## 화면별 디자인

### 📱 메인 화면 (main.dart)

#### AppBar
- 왼쪽: 로고 아이콘 (monitor_heart_outlined) + 제목
- 오른쪽: History, Profile, Settings 아이콘 버튼

#### 측정 상태 카드
- 배경: 측정 중일 때 녹색 그라데이션, 대기 중일 때 다크 그라데이션
- 아이콘: 원형 배경 + 상태 아이콘
- 정보: 데이터 수, 샘플링 레이트
- 진행률 바: 측정 중일 때 표시

#### 피로도 결과 카드
- 배경: 피로도에 따른 그라데이션 (녹색 → 빨간색)
- 레벨 배지: 반투명 흰색 배경 + 레벨 텍스트
- 게이지: FatigueGaugeWidget
- 점수: 큰 숫자 표시 (monospace font)

#### 측정 데이터 카드
- 배경: 다크 카드 배경
- 각 메트릭: 아이콘 + 레이블 + 값 + 설명
- 둥근 모서리 컨테이너로 각 항목 구분

#### 컨트롤 버튼
- 측정 시작: 녹색 그라데이션 + 큰 버튼
- 측정 중지: 빨간색 + 큰 버튼

---

### 📊 측정 기록 화면 (measurement_history_page.dart)

#### AppBar
- 탭: 추이 / 캘린더
- 녹색 indicator

#### 세션 카드
- 배경: 다크 카드
- 왼쪽: 피로도 원형 배지 (그라데이션 + 숫자)
- 중간: 피로도 레벨, 시간, 통계
- 오른쪽: 화살표 아이콘

#### 통계 요약
- 다크 카드 배경
- 그리드 레이아웃
- 녹색 아이콘 + 값

#### 차트
- fl_chart 사용
- 녹색 라인
- 다크 배경

---

### 👤 프로필 화면 (profile_page.dart)

#### 프로필 요약 카드
- 배경: 녹색 그라데이션
- 중앙: 원형 아이콘 (favorite_border)
- 하단: 총 측정 횟수, 평균 피로도

#### ML Phase 카드
- 배경: Phase별 그라데이션 (파란색/보라색/진보라색)
- 상단: Phase 아이콘 + 이름
- 중간: 진행률 바
- 하단: 특징 리스트

#### Baseline 카드
- 배경: 다크 카드
- RMS Base / Freq Base 표시
- 캘리브레이션 상태
- 업데이트 이력

#### 통계 카드
- 다크 카드 배경
- 녹색 아이콘
- 평균, 최소, 최대 피로도

---

## 애니메이션 및 인터랙션

### 터치 피드백
```dart
Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(20),
    child: ...
  ),
)
```

### 그림자
```dart
boxShadow: [
  BoxShadow(
    color: Colors.black.withOpacity(0.3),
    blurRadius: 10,
    offset: Offset(0, 5),
  ),
]
```

### 그라데이션
```dart
gradient: LinearGradient(
  colors: [startColor, endColor],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```

---

## 아이콘 사용

### 메인 화면
- 측정 준비: `touch_app_outlined`
- 측정 중: `monitor_heart`
- 측정 완료: `check_circle`
- 데이터: `data_usage`
- 샘플링: `speed`

### 피로도 레벨
- 정상: `sentiment_very_satisfied`
- 약간 피로: `sentiment_satisfied`
- 피로 누적: `sentiment_dissatisfied`
- 고피로: `sentiment_very_dissatisfied`

### 측정 데이터
- RMS: `graphic_eq`
- Variance: `show_chart`
- Frequency: `multiline_chart`

### 네비게이션
- 기록: `history_outlined`
- 프로필: `person_outline`
- 설정: `settings_outlined`

### ML Phase
- EMA: `functions`
- Hybrid: `hub`
- End-to-End: `psychology`

---

## 레이아웃 가이드

### 패딩
- 페이지 전체: `16px`
- 카드 내부: `20px` ~ `24px`
- 작은 요소: `8px` ~ `12px`

### 간격
- 카드 간: `16px`
- 섹션 간: `20px` ~ `24px`
- 요소 간: `8px` ~ `12px`

### 모서리
- 카드: `borderRadius: 20`
- 작은 컨테이너: `borderRadius: 12`
- 아이콘 버튼: `borderRadius: 10`
- 배지: `borderRadius: 20`

### 폰트
- 헤드라인: `24px bold`
- 타이틀: `18px ~ 20px bold`
- 본문: `14px ~ 16px`
- 캡션: `11px ~ 12px`
- 숫자: `monospace font` 사용

---

## 다크 모드 전용 디자인

### 투명도 활용
- 레이어링: `Colors.white.withOpacity(0.05 ~ 0.2)`
- 구분선: `Colors.white.withOpacity(0.1)`
- 텍스트: `Colors.white.withOpacity(0.5 ~ 0.7)`

### 대비 강화
- 중요한 값: `Colors.white` (100% opacity)
- 일반 텍스트: `Colors.white70`
- 부가 정보: `Colors.white60` or `.withOpacity(0.6)`

---

## 접근성

### 색상 대비
- 텍스트 vs 배경: 최소 4.5:1 비율 유지
- 아이콘 vs 배경: 최소 3:1 비율 유지
- 녹색 (#00E676)은 다크 배경 (#0A0E27)에서 충분한 대비

### 터치 영역
- 최소 터치 영역: 48x48 dp
- 버튼 패딩: 최소 16px vertical

---

## 구현 예제

### 측정 상태 카드
```dart
Container(
  decoration: AppTheme.cardDecoration(
    gradient: isCollecting 
        ? AppTheme.primaryGradient 
        : AppTheme.darkGradient,
  ),
  padding: EdgeInsets.all(24),
  child: Column(
    children: [
      // 아이콘
      Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 48),
      ),
      // 상태 텍스트
      Text(
        status,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      // 통계
      Row(
        children: [
          _buildStatItem(...),
          Divider(),
          _buildStatItem(...),
        ],
      ),
    ],
  ),
)
```

### 메트릭 행
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.05),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      // 아이콘
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primaryGreen),
      ),
      // 정보
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: captionStyle),
          Text(value, style: titleStyle),
          Text(subtitle, style: captionStyle),
        ],
      ),
    ],
  ),
)
```

---

## 파일 구조

```
lib/
├── theme/
│   └── app_theme.dart          # 통합 테마 정의
├── main.dart                   # 메인 화면 (다크 테마 적용)
├── screens/
│   ├── measurement_history_page.dart  # 측정 기록 (다크 테마)
│   └── profile_page.dart             # 프로필 (다크 테마)
└── widgets/
    └── fatigue_gauge.dart     # 피로도 게이지
```

---

## 디자인 원칙

### 1. 일관성 (Consistency)
- 모든 화면에서 동일한 컬러 팔레트
- 동일한 카드 스타일 (borderRadius, shadow)
- 동일한 버튼 스타일

### 2. 계층 구조 (Hierarchy)
- 중요도에 따른 크기 차별화
- 그라데이션으로 강조
- 피로도 점수는 가장 크게 표시

### 3. 가독성 (Readability)
- 다크 배경에서 충분한 대비
- monospace font로 숫자 정렬
- 적절한 간격과 패딩

### 4. 피드백 (Feedback)
- InkWell로 터치 피드백
- 상태 변화 시 그라데이션 변경
- 진행률 바로 상태 표시

---

## 반응형 대응

### 패딩 조절
```dart
padding: EdgeInsets.symmetric(
  horizontal: MediaQuery.of(context).size.width * 0.05,
  vertical: 16,
)
```

### 폰트 크기
```dart
fontSize: MediaQuery.of(context).size.width < 360 ? 16 : 18
```

---

## 미래 개선사항

### 1. 애니메이션 추가
- 카드 등장: Fade + Slide
- 숫자 변화: Counter animation
- 그래프: Line drawing animation

### 2. 다크/라이트 모드 전환
- 현재: 다크 모드 only
- 계획: 토글 스위치로 전환 가능

### 3. 커스텀 폰트
- 헤드라인: 굵은 sans-serif
- 숫자: monospace (이미 적용)
- 본문: 읽기 쉬운 sans-serif

---

## 참고 자료

- [Fitness Health Tracker UI Kit](https://kr.pinterest.com/pin/1145532855445326431/)
- [Material Design Dark Theme](https://material.io/design/color/dark-theme.html)
- [Flutter Material 3](https://docs.flutter.dev/ui/design/material)

