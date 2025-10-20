# 🎨 Color Palette

## 최종 컬러 팔레트 (2025-01-20)

### 배경 컬러 (다크 그레이 계열)

```dart
darkBackground = #121212  // Material Dark 표준 배경
cardBackground = #1E1E1E  // 카드 배경 (약간 밝은 검은색)
cardDark       = #181818  // 카드 어두운 부분
```

**참고**: [Pinterest Fitness Health Tracker UI](https://kr.pinterest.com/pin/1145532855445326431/)의 검은색 계열 디자인 적용

### 메인 컬러 (녹색 계열)

```dart
primaryGreen = #00E676  // 메인 녹색 (Material Green A400)
darkGreen    = #00C853  // 어두운 녹색 (Material Green A700)
accentGreen  = #69F0AE  // 연한 녹색 (Material Green A200)
```

### 피로도 레벨 컬러

```dart
정상      = #00E676  // 녹색
약간 피로 = #FFEB3B  // 노란색 (Material Yellow)
피로 누적 = #FF9800  // 오렌지 (Material Orange)
고피로    = #E53935  // 빨간색 (Material Red)
```

### ML Phase 컬러

```dart
Phase 1 (EMA)        = #2196F3  // 파란색 (Material Blue)
Phase 2 (Hybrid)     = #AB47BC  // 보라색 (Material Purple)
Phase 3 (End-to-End) = #7B1FA2  // 진보라색 (Material Purple Dark)
```

---

## 색상 사용 예시

### 배경 레이어링
```dart
// 메인 배경
Scaffold(
  backgroundColor: AppTheme.darkBackground,  // #121212
)

// 카드
Container(
  decoration: AppTheme.cardDecoration(),  // #1E1E1E
)

// 중첩된 카드/섹션
Container(
  color: AppTheme.cardDark,  // #181818
)
```

### 텍스트 컬러 (다크 배경 기반)
```dart
// 메인 텍스트
color: Colors.white  // #FFFFFF (100% opacity)

// 일반 텍스트
color: Colors.white.withOpacity(0.87)  // 87% (Material 권장)

// 부가 텍스트
color: Colors.white.withOpacity(0.6)   // 60%

// 비활성 텍스트
color: Colors.white.withOpacity(0.38)  // 38%
```

### 구분선/보더
```dart
// 구분선
color: Colors.white.withOpacity(0.12)

// 카드 보더
color: primaryGreen.withOpacity(0.3)

// 레이어 배경
color: Colors.white.withOpacity(0.05)
```

---

## 접근성 (WCAG 대비 비율)

### 배경 대비
| 텍스트 | 배경 | 대비 비율 | WCAG 등급 |
|--------|------|-----------|-----------|
| #FFFFFF (흰색) | #121212 | 15.8:1 | AAA ✅ |
| #00E676 (녹색) | #121212 | 10.2:1 | AAA ✅ |
| #FFFFFF (흰색) | #1E1E1E | 14.1:1 | AAA ✅ |
| #00E676 (녹색) | #1E1E1E | 9.1:1 | AAA ✅ |

**결과**: 모든 주요 조합이 WCAG AAA 등급 충족 ✅

---

## 그라데이션

### Primary Gradient
```dart
LinearGradient(
  colors: [#00E676, #00C853],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```

### Dark Gradient
```dart
LinearGradient(
  colors: [#1E1E1E, #181818],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```

### Fatigue Gradient (동적)
```dart
피로도 < 1.5: [#00E676, #00C853]  // 녹색
피로도 < 2.5: [#FFEB3B, #FFC107]  // 노란색
피로도 < 3.5: [#FF9800, #F57C00]  // 오렌지
피로도 >= 3.5: [#E53935, #C62828]  // 빨간색
```

---

## 디자인 시스템

### Material Design Dark Theme 기준
- 배경: #121212 (0dp elevation)
- Surface: #1E1E1E (1-8dp elevation)
- Primary: #00E676
- On Primary: #000000 (검은색 텍스트 on 녹색 배경)
- On Surface: #FFFFFF (흰색 텍스트 on 검은색 배경)

### 그림자 (Elevation)
```dart
// 낮은 elevation (카드)
boxShadow: [
  BoxShadow(
    color: Colors.black.withOpacity(0.3),
    blurRadius: 10,
    offset: Offset(0, 5),
  ),
]

// 높은 elevation (다이얼로그)
boxShadow: [
  BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 20,
    offset: Offset(0, 10),
  ),
]
```

---

## 참고 자료
- [Pinterest - Fitness Health Tracker UI](https://kr.pinterest.com/pin/1145532855445326431/)
- [Material Design - Dark Theme](https://material.io/design/color/dark-theme.html)
- [Material Color Tool](https://material.io/resources/color/)
- [WCAG Contrast Checker](https://webaim.org/resources/contrastchecker/)

