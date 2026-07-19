# Match-up 2026 디자인 리뉴얼 — 통합 Spec

> **보관 문서:** 이 문서의 컬러·형태·컴포넌트 방향은 2026-07-18부터
> [`pureform-sports-system.md`](pureform-sports-system.md)로 대체되었다.
> 과거 의사결정 이력 확인 용도로만 사용한다.

생성: 2026-05-09
출처: 3 agent 병렬 리서치 (현재 진단 / 2026 트렌드 / Flutter 디자인 시스템)
사용자 결정: **옵션 B** — 토큰 + 핵심 컴포넌트 우선 (1.5~2일), 그 후 신규 화면(C5/C6 multi-org) 새 디자인으로 작성, 기존 7개 화면 점진 마이그레이션

---

## Part 1. 현재 진단 — ★ 2/5

### 종합
"Material 3 빈 캔버스에 기능만 빠르게 채운 MVP. 2026 한국 MZ 사용자가 보면 즉시 olds 인식."

### 가장 큰 문제 3가지
1. **Material 3 OOTB 증후군** — 9개 화면 전부 `Card+ListTile+OutlineInputBorder+FilledButton` 디폴트. 커스텀 위젯 1개(`tournament_card`도 ListTile 래퍼)
2. **타이포·컬러 시스템 부재** — `colorSchemeSeed: 0xFF2E7D32` 한 줄. Pretendard 미적용, 하드코딩 컬러 8건, 다크모드 0
3. **모션·인터랙션 빈곤** — 햅틱 0, 스켈레톤 0, hero 0, 마이크로 인터랙션 0

### 가장 olds한 화면 Top 3
- **profile_screen** — 9 ListTile + 3 Divider (안드로이드 4 시절 설정)
- **tournament_detail** — 모든 정보가 동일 height 32px row (위계 0)
- **chat_screen** — 말풍선이 `Card` (LINE 2015 디자인)

### Quick wins (1~2일 내 가능)
1. Pretendard 적용 (한글 가독성 +30%)
2. TournamentCard 리디자인 (9개 화면 중 3개에 즉시 영향)
3. 하드코딩 컬러 → `Theme.of(context).colorScheme.*`
4. 모서리 radius 4 → 16
5. 카카오 노란색 살리기 (login)
6. Lottie 일러스트 (empty state)
7. 챗봇 말풍선 radius + 꼬리
8. 홈 헤더에 hero 카드
9. 햅틱 + 즐겨찾기 토글 마이크로 인터랙션

---

## Part 2. 2026 트렌드 핵심 7가지

### 글로벌
1. **Liquid Glass** (iOS 26) — 동적 머티리얼, 상단 UI에만
2. **Material 3 Expressive** (Google I/O 2025) — Spring physics, Shape morphing
3. **Bento Grid** — 비대칭 모듈 카드 (Apple App Store, Notion, Linear)
4. **AI-First UI** — 챗봇 박스 탈피, 인용 카드·suggested chips, 출처 신뢰도
5. **Big Number / Hero Metric** — 첫 화면 큰 숫자 1개 (Toss, Strava, Apple Fitness)
6. **Spring 마이크로 인터랙션 + 햅틱** (Toss·iOS 26)
7. **다크모드 = 기본** + surface 5단 분리

### 한국 특화
- **Toss TDS** — Pretendard + 자체 Toss Product Sans, typography 토큰 추상화
- **당근 SEED Design System** — Figma 1벌로 다크/iOS/Android 자동
- **Pretendard Variable** — 한국 모바일 사실상 표준 (OFL)
- **카카오 Tossface** — 이모지 + 한글 디스플레이 헤더 패턴
- **캐치테이블** — 한 화면 한 결정 (Match-up "대회 신청" 동선 참고)
- **SOCAR FRAME** — 다크모드 기본색 200 톤 (#0E1411 같은 미드나잇 그린)

### 직접 비교 — 동호인·스포츠 앱
| 앱 | Match-up이 배울 점 |
|----|---|
| **스매시** (직접 경쟁) | "내 등급 출전 가능 N개" Hero metric — 매칭 위주 vs 대회/등급 차별화 |
| **베이스라인** | Duotone 아이콘 + 진입 stagger 80ms |
| **Strava** (2025 redesign) | 지도+메트릭 오버레이 (대회 상세에 적용) |
| **카카오맵 AI메이트** | 대화형 입력 + 추천 카드 + 출처 칩 (챗봇 답변 형식) |
| **캐치테이블** | 빈자리 알림 + 단계 분리 결제 |
| **Toss 홈** | Bento + Big Number + Pretendard (홈 그대로 차용 가능) |

---

## Part 3. 디자인 시스템 결정 (Flutter)

### 핵심 결정 트리

| 결정 | 권장 |
|------|------|
| 본문 폰트 | **Pretendard Variable** (OFL, variable font 1 file = 9 weights) |
| 시드 컬러 | `#2E7D32` 코트그린 유지 |
| 보조 컬러 | 테니스 옐로우 `#E8C547` (secondary), 풋살 코랄 `#F4511E` (tertiary) |
| ColorScheme 생성 | 명시 토큰 (`ColorScheme.light()` 12개 직접 정의) — surfaceContainer* 5단 |
| 디폴트 모서리 | 컴포넌트 12, 카드 16, hero 20, 모달 28, pill 999 |
| Card elevation | 0 (filled) — 그림자는 BoxShadow 직접, 다크는 surface 단계로 깊이 |
| 다크모드 | 시스템 추종 + 사용자 토글 (SharedPreferences) |
| Skeleton | `skeletonizer` 패키지 (pub.dev 404k+ 다운로드) |
| 모션 | M3 short(50~200ms) / medium(250~400) / long(450~600) + emphasized cubic |

### 컬러 토큰 (Light)
- primary: `#2E7D32` / onPrimary: `#FFFFFF`
- primaryContainer: `#B6F0BC` / onPrimaryContainer: `#002106`
- secondary: `#8A6A00` (테니스 옐로우 톤다운)
- tertiary: `#B23A0E` (풋살 오렌지 톤다운)
- surface: `#FCFDF7` (off-white, 살짝 그린)
- surfaceContainerLowest~Highest: 5단 그라데이션
- error: `#BA1A1A` / outline: `#727970`

### 컬러 토큰 (Dark)
- primary: `#9BD3A2` / onPrimary: `#003910`
- secondary: `#E8C547` (다크는 풀 채도)
- tertiary: `#FFB59B`
- surface: `#101411` (미드나잇 그린, 풀블랙 X)
- surfaceContainerLowest~Highest: 5단

### 타이포 (Pretendard, 한글 자간 -2%, 행간 1.5)
- displayLarge 36/700, displayMedium 30/700
- headlineLarge 26/700, headlineMedium 22/700, headlineSmall 18/600
- titleLarge 17/600, titleMedium 15/600, titleSmall 13/600
- bodyLarge 16/400 (행간 1.55), bodyMedium 14/400, bodySmall 12/400
- labelLarge 14/600, labelMedium 12/600, labelSmall 11/600

### 컴포넌트 라이브러리 (10개)

| 위젯 | 역할 | 우선순위 |
|------|------|---------|
| `AppCard` | Card 대체 — filled/outlined/elevated 3 variant | High (모든 화면) |
| `AppChip` | FilterChip/ChoiceChip 통합 | High (필터·등급) |
| `AppButtons` | Primary/Secondary/Ghost (52pt height, pill radius) | High |
| `AppEmptyState` | 빈 상태 — 원형 아이콘 + CTA | High (3 화면) |
| `AppListSection` | 리스트 헤더 + 액션 + 카드 묶음 | Medium |
| `AppInfoTile` | ListTile 대체 — 좌측 색 박스 + 라벨 + 값 | Medium |
| `AppSkeletonCard` | `skeletonizer` 래퍼 — 자동 shimmer | Low |
| `AppToast` | SnackBar 커스텀 — info/success/warning/error | Low |
| `AppHeroSection` | 홈 hero — 그라디언트 + Big Number + CTA | High (홈 변경) |
| `AppBottomNav` | NavigationBar 커스텀 — duotone 아이콘 | Medium |

### 모션 토큰
```
short1=50, short2=100, short3=150, short4=200ms
medium1=250, medium2=300, medium3=350, medium4=400ms
long1=450, long2=500, long3=550, long4=600ms

standard, standardDecelerate, standardAccelerate,
emphasized, emphasizedDecelerate, emphasizedAccelerate (cubic)
```

| 인터랙션 | duration | curve |
|---|---|---|
| Chip 토글 | 150 | standard |
| 버튼 ripple | 100 | standard |
| 카드 focus | 200 | standardDecelerate |
| 모달 진입 | 400 | emphasizedDecelerate |
| 페이지 전환 | 500 | emphasized |

### 다크모드
- ThemeMode provider (Riverpod + SharedPreferences)
- 프로필 화면에 SegmentedButton 토글 (system / light / dark)
- 그림자는 다크에서 거의 없애고 surface 단계로 깊이

---

## Part 4. 작업 청크 (옵션 B 선택)

### Phase 0 — 토큰 도입 (0.5일)
- [ ] `assets/fonts/PretendardVariable.ttf` 추가 (2.1MB)
- [ ] `pubspec.yaml`: fonts 블록 + `skeletonizer` 의존성
- [ ] `lib/theme/{tokens,typography,color_schemes,app_theme,motion}.dart` 5개 신규
- [ ] `lib/state/theme_provider.dart` 신규 (ThemeMode)
- [ ] `lib/main.dart`: light/dark/themeMode 적용

### Phase 1 — 컴포넌트 라이브러리 (1~1.5일)
- [ ] `lib/widgets/app_card.dart`
- [ ] `lib/widgets/app_chip.dart`
- [ ] `lib/widgets/app_buttons.dart`
- [ ] `lib/widgets/app_empty_state.dart`
- [ ] `lib/widgets/app_list_section.dart`
- [ ] `lib/widgets/app_info_tile.dart`
- [ ] `lib/widgets/app_skeleton_card.dart`
- [ ] `lib/widgets/app_toast.dart`
- [ ] `lib/widgets/app_hero_section.dart`
- [ ] `lib/widgets/app_bottom_nav.dart`
- [ ] `lib/widgets/tournament_card.dart` 리팩토링 (AppCard 위에)

### Phase 2 — 신규 화면을 새 디자인으로 (C5/C6 통합)
- [ ] `onboarding_screen.dart` 재작성 — 다단계 + 권역 + multi-org 카드 + 새 컴포넌트
- [ ] `profile_screen.dart` 재작성 — hero 헤더 + 카드 그룹 + 다크모드 토글 + multi-org 표시

### Phase 3 — 기존 7 화면 점진 마이그레이션 (별도 청크)
- [ ] home_screen — Hero + Bento + 새 카드
- [ ] tournaments list/detail/submit
- [ ] clubs / rules / chat / login

### Phase 4 — 검증
- [ ] flutter analyze 0 warnings
- [ ] light/dark 토글 시 모든 화면 정상
- [ ] Pretendard 한글 자간·행간 시각 확인
- [ ] WCAG AA 대비비 ≥ 4.5

---

## Part 5. 다음 단계

본 spec 작성 후:
1. Phase 0 (토큰 도입) commit
2. Phase 1 (컴포넌트 10개) commit
3. C5 multi-org 온보딩 — 새 컴포넌트로
4. C6 multi-org 프로필 — 새 컴포넌트로
5. 기존 화면 마이그레이션 (Phase 3)는 별도 PR

---

## 참고 자료 (출처)

### 트렌드
- [Apple Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [Material 3 Expressive 발표](https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch/)
- [Bento Grid 2026 가이드](https://senorit.de/en/blog/bento-grid-design-trend-2025)
- [미리 보는 2026 UI·UX 트렌드 (DesignDB)](https://www.designdb.com/?menuno=1278&bbsno=3012&siteno=15&act=view)
- [TDS Mobile 문서 (Toss)](https://tossmini-docs.toss.im/tds-mobile/)
- [SEED Design System (당근)](https://seed-design.io/)
- [SOCAR FRAME 다크모드 #2](https://tech.socarcorp.kr/design/2020/07/22/dark-mode-02.html)
- [카카오맵 AI메이트 로컬](https://www.kakaocorp.com/page/detail/11619)

### 폰트·기술
- [Pretendard GitHub](https://github.com/orioncactus/pretendard)
- [Pretendard OFL License](https://github.com/orioncactus/pretendard/blob/main/LICENSE)
- [Flutter ColorScheme.fromSeed](https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.fromSeed.html)
- [M3 Easing & Duration](https://m3.material.io/styles/motion/easing-and-duration)
- [M3 Shape / Corner Radius Scale](https://m3.material.io/styles/shape/corner-radius-scale)
- [skeletonizer (pub.dev)](https://pub.dev/packages/skeletonizer)

### 직접 경쟁자
- [스매시 SMAXH App Store](https://apps.apple.com/kr/app/%EC%8A%A4%EB%A7%A4%EC%8B%9C-%ED%85%8C%EB%8B%88%EC%8A%A4-%ED%8C%8C%ED%8A%B8%EB%84%88-%EB%A7%A4%EC%B9%AD-%EC%BD%94%ED%8A%B8-%EC%98%88%EC%95%BD/id1605089284)
- [Strava Record 리디자인](https://press.strava.com/articles/strava-launches-redesigned-record-experience)
