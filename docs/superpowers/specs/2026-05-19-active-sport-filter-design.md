# 설계: 전역 활성 종목 필터 (2026-05-19)

## 개요

사용자가 가입 또는 프로필에서 선택한 primary 종목을 앱 전체의 기본 필터로 적용한다.
현재는 각 화면이 독립적인 수동 종목 칩을 갖거나 전체 종목을 동시에 표시해 사용자 의도와 무관한 콘텐츠가 섞인다.

---

## 1. 상태 설계

### 추가: `activeSportProvider`

```dart
// state/providers.dart
final activeSportProvider = Provider<String?>((ref) {
  final sports = ref.watch(userSportsProvider).valueOrNull ?? [];
  final primary = sports.firstWhereOrNull((s) => s.isPrimary);
  return primary?.sport; // 'tennis' | 'futsal' | null
});
```

- `userSportsProvider`에서 파생 — 별도 상태 없음
- 세션 변경 / 프로필 수정 시 자동 재계산
- `null`: 종목 미등록 상태 (온보딩 전)

### 제거: `selectedSportProvider`

현재 `StateProvider<String?>`로 존재하나 `activeSportProvider`로 대체한다.
`homeTournamentsProvider`도 `activeSportProvider`를 참조하도록 변경.

---

## 2. 화면별 변경

### 2-1. 대회 탭 (`tournaments_screen.dart`)

**현재:** 수동 종목 칩("전체 종목 / 테니스 / 풋살") + `selectedSportProvider`
**변경:**
- 수동 종목 칩 제거
- `_MyGradeSection`이 `activeSportProvider`를 읽어 자동 필터
- 전체 검색 섹션도 `activeSportProvider` 기본값으로 시작 (사용자가 별도 변경 불가)
- `activeSportProvider == null`이면 기존대로 전체 표시

### 2-2. 클럽 탭 (`clubs_screen.dart`)

**현재:** 수동 종목 칩("전체 / 테니스 / 풋살") + 로컬 `_sport` state
**변경:**
- 종목 칩 제거
- 화면 초기화 시 `activeSportProvider` 값으로 `api.searchClubs(sport: activeSport)` 호출
- `activeSportProvider == null`이면 전체 클럽 표시

### 2-3. 룰북 탭 (`rules_screen.dart`)

**현재:** 테니스 탭 + 풋살 탭 항상 둘 다 표시
**변경:**
- `activeSportProvider`가 있으면 해당 종목 단일 표시 (TabBar 제거, 단순 ListView)
- `activeSportProvider == null`이면 기존 탭 유지 (종목 미등록 사용자)

### 2-4. 채팅 (`chat_screen.dart` + `chat/index.ts`)

**Flutter 측:** 변경 없음 — 백엔드가 `user_sports`를 이미 조회함
**백엔드 확인:** `chat/index.ts`의 `buildSystemPrompt()`가 `user_sports`에서 primary 종목을 강조하도록 수정

```typescript
// 현재: sport 목록만 나열
// 변경: primary 종목을 "주요 관심 종목"으로 명시
const primarySport = userSports.find(s => s.is_primary);
if (primarySport) {
  prompt += `\n사용자의 주요 관심 종목: ${primarySport.sport} (${primarySport.grade})`;
}
```

### 2-5. 프로필 (`profile_screen.dart`)

- 현재 primary 종목을 "활성 종목" 레이블로 명확히 표시
- "종목 변경" → 온보딩 화면으로 이동 (기존 동작 유지)
- primary 변경 후 `userSportsProvider` invalidate → `activeSportProvider` 자동 갱신

---

## 3. 온보딩 (`onboarding_screen.dart`)

변경 없음. 이미 `is_primary` 선택 UI가 있음.
단, primary를 명확히 "앱 전체 기본 종목"으로 설명하는 레이블 추가:

```
"Primary 종목" → "앱 기본 종목 (대회·클럽·룰북 필터에 사용됩니다)"
```

---

## 4. `homeTournamentsProvider` 수정

```dart
// 현재: selectedSportProvider 참조
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final sport = ref.watch(selectedSportProvider); // 변경 전
  ...
});

// 변경 후: activeSportProvider 참조
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final sport = ref.watch(activeSportProvider); // 변경 후
  ...
});
```

---

## 5. 엣지 케이스

| 상황 | 처리 |
|------|------|
| 종목 미등록 (`activeSport == null`) | 전체 콘텐츠 표시, 온보딩 유도 배너 |
| 단일 종목 등록 | 종목 칩/탭 UI 숨김 (불필요) |
| 두 종목 등록 | primary만 기본 표시, 프로필에서 변경 |
| primary 변경 | `userSportsProvider` invalidate → 모든 화면 즉시 갱신 |

---

## 6. 변경 파일 요약

| 파일 | 변경 |
|------|------|
| `app/lib/state/providers.dart` | `activeSportProvider` 추가, `selectedSportProvider` 제거, `homeTournamentsProvider` 수정 |
| `app/lib/screens/tournaments/tournaments_screen.dart` | 수동 종목 칩 제거, `activeSportProvider` 사용 |
| `app/lib/screens/clubs_screen.dart` | 종목 칩 제거, `activeSportProvider` 사용 |
| `app/lib/screens/rules_screen.dart` | 단일 종목 뷰 + 탭 조건부 표시 |
| `app/lib/screens/auth/onboarding_screen.dart` | primary 설명 레이블 수정 |
| `app/lib/screens/profile_screen.dart` | "활성 종목" 레이블 표시 |
| `supabase/functions/chat/index.ts` | buildSystemPrompt에 primary 종목 강조 |
