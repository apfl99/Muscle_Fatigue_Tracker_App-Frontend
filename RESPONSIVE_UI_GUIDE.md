# 📱 반응형 UI 가이드

## 개요
모든 기기에서 UI가 정상 출력되도록 적응형 UI 시스템 구축

---

## 반응형 시스템

### 📐 화면 크기 기준

```dart
// utils/responsive.dart

Small Screen:  width <= 360px  (작은 폰)
Medium Screen: 360px < width <= 600px (일반 폰)
Large Screen:  width > 600px   (태블릿)
```

### 🔧 주요 함수

#### 1. 화면 크기 확인
```dart
Responsive.isSmallScreen(context)   // <= 360px
Responsive.isMediumScreen(context)  // 360-600px
Responsive.isLargeScreen(context)   // > 600px
```

#### 2. 반응형 패딩
```dart
// 자동 패딩 (화면 크기에 따라)
Responsive.responsivePadding(context)
// Small: 12px, Medium: 16px, Large: 20px

// 카드 패딩
Responsive.cardPadding(context)
// Small: 16px, Medium: 20px, Large: 24px
```

#### 3. 화면 비율 계산
```dart
// 화면 너비의 50%
Responsive.wp(context, 50)

// 화면 높이의 30%
Responsive.hp(context, 30)
```

---

## 적용된 반응형 요소

### 메인 화면 (main.dart)

| 요소 | Small (≤360px) | Medium/Large (>360px) |
|------|----------------|----------------------|
| 페이지 패딩 | 12px | 16px |
| 카드 패딩 | 16px | 20-24px |
| AppBar 제목 | 18px | 22px |
| 상태 아이콘 | 40px | 48px |
| 상태 텍스트 | 20px | 24px |
| 버튼 높이 | 56px | 60px |
| 버튼 아이콘 | 24px | 28px |
| 버튼 텍스트 | 16px | 18px |
| 피로도 점수 | 40px | 48px |
| 메트릭 값 | 18px | 22px |

### 측정 기록 화면 (measurement_history_page.dart)

| 요소 | Small | Medium/Large |
|------|-------|--------------|
| 세션 카드 간격 | 8px | 12px |
| 카드 패딩 | 16px | 20px |
| 피로도 원형 | 50x50 | 60x60 |
| 피로도 숫자 | 16px | 18px |
| 레벨 텍스트 | 14px | 16px |
| 메트릭 텍스트 | 10px | 11px |

### 프로필 화면 (profile_page.dart)

| 요소 | Small | Medium/Large |
|------|-------|--------------|
| 프로필 아이콘 | 70x70 | 80x80 |
| 아이콘 크기 | 32px | 40px |
| 프로필 제목 | 18px | 20px |
| 카드 패딩 | 16px | 20-24px |

---

## Overflow 방지 전략

### 1. Flexible/Expanded 사용
```dart
// 긴 텍스트
Row(
  children: [
    Flexible(
      child: Text(
        longText,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

### 2. SingleChildScrollView
```dart
// 전체 페이지
body: SingleChildScrollView(
  padding: Responsive.responsivePadding(context),
  child: Column(...),
)
```

### 3. 반응형 크기
```dart
// 고정 크기 대신 조건부 크기
fontSize: Responsive.isSmallScreen(context) ? 16 : 18
```

### 4. 텍스트 Overflow 처리
```dart
Text(
  value,
  overflow: TextOverflow.ellipsis,  // 넘치면 ...
  maxLines: 1,                       // 한 줄로 제한
)
```

---

## 화면별 주요 개선사항

### 📱 메인 화면

#### AppBar
- ✅ 제목에 `Flexible` 적용
- ✅ 작은 화면에서 폰트 축소
- ✅ `overflow: TextOverflow.ellipsis`

#### 상태 카드
- ✅ 아이콘 크기 반응형
- ✅ 텍스트 크기 반응형
- ✅ 패딩 반응형

#### 피로도 카드
- ✅ 레벨 배지 크기 반응형
- ✅ 점수 폰트 반응형 (40px/48px)
- ✅ `Flexible`로 Overflow 방지

#### 측정 데이터 카드
- ✅ 메트릭 값 폰트 반응형 (18px/22px)
- ✅ 아이콘 크기 반응형
- ✅ `Expanded`로 텍스트 공간 확보

#### 버튼
- ✅ 높이 반응형 (56px/60px)
- ✅ 텍스트에 `Flexible` 적용
- ✅ `overflow: TextOverflow.ellipsis`

### 📊 측정 기록 화면

#### 세션 카드
- ✅ 카드 간격 반응형
- ✅ 원형 배지 크기 반응형
- ✅ 모든 텍스트에 `Flexible` + `overflow`
- ✅ 폰트 크기 반응형

### 👤 프로필 화면

#### 프로필 요약
- ✅ 아이콘 크기 반응형
- ✅ 제목 폰트 반응형
- ✅ 패딩 반응형

---

## 테스트 해야 할 기기

### 작은 화면 (≤360px)
- iPhone SE (1st gen): 320x568
- iPhone SE (2nd gen): 375x667
- Samsung Galaxy S21: 360x800

### 중간 화면 (360-600px)
- iPhone 11 Pro: 375x812
- iPhone 12/13: 390x844
- Pixel 5: 393x851

### 큰 화면 (>600px)
- iPhone 14 Pro Max: 430x932
- iPad Mini: 768x1024
- iPad Pro: 1024x1366

---

## 사용 예시

### 반응형 폰트 크기
```dart
Text(
  'Hello',
  style: TextStyle(
    fontSize: Responsive.isSmallScreen(context) ? 16 : 18,
  ),
)
```

### 반응형 패딩
```dart
Container(
  padding: Responsive.cardPadding(context),
  child: ...
)
```

### 반응형 크기
```dart
Container(
  width: Responsive.isSmallScreen(context) ? 50 : 60,
  height: Responsive.isSmallScreen(context) ? 50 : 60,
)
```

### Flexible 사용
```dart
Row(
  children: [
    Icon(...),
    SizedBox(width: 8),
    Flexible(
      child: Text(
        longText,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

---

## 체크리스트

### ✅ 완료된 항목
- [x] Responsive 유틸리티 클래스 생성
- [x] 메인 화면 반응형 적용
- [x] 측정 기록 화면 반응형 적용
- [x] 프로필 화면 반응형 적용
- [x] AppBar 제목 Overflow 방지
- [x] 버튼 텍스트 Overflow 방지
- [x] 카드 패딩 반응형
- [x] 폰트 크기 반응형
- [x] 아이콘 크기 반응형

### 🔄 추가 개선 가능 항목
- [ ] 설정 다이얼로그 반응형
- [ ] 차트 크기 반응형
- [ ] 캘린더 크기 반응형
- [ ] 가로 모드 최적화

---

## Overflow 발생 시 디버깅

### 1. 원인 찾기
```dart
// Debug Paint 활성화
flutter run --debug-paint
```

### 2. 확인 사항
- [ ] Row/Column에 Flexible/Expanded 사용했는지
- [ ] 고정 크기 대신 반응형 크기 사용했는지
- [ ] Text에 overflow 처리 했는지
- [ ] 패딩이 과도하지 않은지

### 3. 해결 방법
```dart
// Before (Overflow 발생)
Row(
  children: [
    Container(width: 100),
    Text('Very Long Text Here'),
    Container(width: 100),
  ],
)

// After (Overflow 해결)
Row(
  children: [
    Container(width: 100),
    Flexible(
      child: Text(
        'Very Long Text Here',
        overflow: TextOverflow.ellipsis,
      ),
    ),
    Container(width: 100),
  ],
)
```

---

## 성능 최적화

### MediaQuery 최적화
```dart
// Bad: 매번 MediaQuery 호출
Text('', style: TextStyle(
  fontSize: MediaQuery.of(context).size.width < 360 ? 14 : 16,
))

// Good: 한 번만 확인
Widget build(BuildContext context) {
  final isSmall = Responsive.isSmallScreen(context);
  
  return Text('', style: TextStyle(
    fontSize: isSmall ? 14 : 16,
  ));
}
```

---

## 참고 자료
- [Flutter Responsive Design](https://docs.flutter.dev/ui/adaptive-responsive)
- [Material Design Responsive](https://material.io/design/layout/responsive-layout-grid.html)
- [MediaQuery Best Practices](https://api.flutter.dev/flutter/widgets/MediaQuery-class.html)

