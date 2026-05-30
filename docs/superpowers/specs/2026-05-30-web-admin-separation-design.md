# Web Admin / App User Separation Design

## Summary

Flutter Web 빌드를 어드민 전용 대시보드로 사용하고, 모바일 앱은 일반 사용자 전용으로 분리한다.

## Motivation

- 스토어 심사에 어드민 기능 노출 방지
- 어드민 작업(대회 승인, 크롤 현황, 데이터 편집)은 PC 브라우저가 적합
- 앱 UX를 사용자 동선에만 집중

## Design Decisions

| 결정 | 선택 | 대안 |
|------|------|------|
| 분리 방식 | 라우터 분기 (방식 A) | _MainShell 내부 분기, 별도 엔트리포인트 |
| 웹 레이아웃 | 사이드바 + 탑바 조합 | 사이드바만, 탑 네비게이션 |
| 비어드민 웹 접속 | 로그인 화면 + "관리자 권한 필요" 안내 | 읽기 전용 허용, 앱 다운로드 랜딩 |
| 랜딩페이지 | 지금은 로그인 화면만 (스토어 출시 후 제작) | 즉시 랜딩페이지 제작 |
| 추가 기능 | 기존 5탭 + 대회 수기 편집 | 5탭 그대로, 사용자 관리 포함 |

## Step 1: Web Build Unblock (JY-21)

### Problem

`notifications.dart`가 `dart:io`의 `Platform.isIOS/isAndroid`를 사용.
`main.dart`에서 무조건 import되어 `flutter build web` 컴파일 실패.

### Solution

speed_gun과 동일한 conditional import 패턴:

```
app/lib/services/
  notifications.dart       (기존 모바일 구현, dart:io 유지)
  notifications_web.dart   (신규 no-op stub, dart:io 없음)
```

`main.dart`에서:

```dart
import 'services/notifications.dart'
    if (dart.library.html) 'services/notifications_web.dart';
```

`notifications_web.dart`는 동일 함수 시그니처로 no-op 반환 (웹에서 FCM 불필요).

stub이 export해야 하는 함수 시그니처:

```dart
Future<void> initNotifications(ApiService api) async {}
```

`main.dart`의 `onAuthStateChange` 리스너가 `initNotifications(api)`를 호출하므로,
stub은 이 시그니처를 정확히 맞춰야 한다.

Note: `firebase_messaging`은 웹도 지원하지만 (`firebase-messaging-sw.js` 필요),
MVP에서는 의도적으로 no-op으로 처리한다. 웹 푸시는 Post-MVP 검토.

## Step 2: Router Branching

### Web Redirect Flow

```
비로그인          -> /login
로그인 + 비어드민  -> /no-access ("관리자 권한 필요" + 로그아웃)
로그인 + 어드민    -> /admin (AdminShell)
```

### App Redirect Flow

기존 그대로 유지 (변경 없음).

### Redirect Guard: /admin/* 전체 경로 보호

현재 redirect 로직은 `loc == '/admin'`만 체크한다. 변경 후에는
`/admin/*` 서브라우트 전체를 보호해야 한다:

```dart
if (loc.startsWith('/admin')) {
  final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
  if (!isAdmin) return kIsWeb ? '/no-access' : '/';
}
```

이 가드가 없으면 비어드민이 `/admin/drafts` 직접 접근 시 AdminShell이 렌더된다.
RLS가 데이터를 보호하지만, UI 노출 자체가 정보 유출이므로 반드시 차단.

### Web Onboarding Bypass

웹에서는 onboarding redirect를 skip한다. 어드민은 이미 종목 등록을
완료한 상태이며, 웹에서 온보딩 UI를 제공할 필요가 없다:

```dart
// 기존: sports.isEmpty → /onboarding
// 변경: kIsWeb이면 onboarding skip
if (!kIsWeb && sports.isEmpty) return '/onboarding';
```

### AdminShell Loading State

`isAdminProvider`가 async이므로 AdminShell이 redirect 전에 잠시 렌더될 수 있다.
AdminShell 위젯 내부에서 `isAdminProvider`를 watch하고:
- loading → 중앙 `CircularProgressIndicator`
- false → 자동으로 redirect 발생 (router의 refresh stream이 처리)
- true → 정상 렌더

### _moreSubPaths 정리

`router.dart`의 `_moreSubPaths` 배열에서 `/admin`을 제거한다.
AdminShell이 ShellRoute 밖으로 이동하므로 Bottom Nav 인덱스 로직에서 제외.

### Route Tree Changes

```
// 웹 전용
/no-access          -> NoAccessScreen

// /admin을 ShellRoute 밖으로 이동, AdminShell로 감싸기
AdminShellRoute:
  /admin             -> 대시보드 (크롤 현황 요약)
  /admin/drafts      -> Draft 승인
  /admin/sources     -> 크롤 소스
  /admin/clubs       -> 클럽 승인
  /admin/kb          -> 지식베이스
  /admin/edit/:id    -> 대회 수기 편집 (신규)
```

기존 AdminScreen의 5탭 위젯을 개별 라우트에서 재사용.

## Step 3: AdminShell Layout

```
+--------------------------------------------------+
|  Match-up Admin              [ssfak] [로그아웃]    |  <- TopBar
+----------+---------------------------------------+
| 대시보드  |                                       |
| Draft    |         콘텐츠 영역                     |
| 크롤소스  |      (각 라우트의 위젯)                  |
| 클럽승인  |                                       |
| 지식베이스 |                                       |
| 대회편집  |                                       |
+----------+---------------------------------------+
```

- `Scaffold` + `Row`: 왼쪽 `NavigationRail` 또는 커스텀 사이드바, 오른쪽 `Expanded(child: child)`
- 사이드바 너비: 고정 220px
- 반응형 불필요 (어드민은 PC 전용)

## Step 4: Tournament Edit Screen

`/admin/edit/:id` 라우트. tournaments 테이블 직접 수정.

### Editable Fields

- description
- location
- application_deadline
- eligible_grades (division_codes 선택 UI)
- status (draft/published)

### Behavior

- Supabase client로 직접 update (service_role 불필요, RLS `tournaments_admin_all` 정책 활용)
- 임베딩 재생성: `003_tournaments.sql`의 `tournaments_invalidate_embedding` 트리거가
  title/description/region/format/organizer 변경 시 자동으로 `embedding = null` 설정.
  클라이언트에서 별도로 `embedding = null`을 세팅할 필요 없음.
- 401 응답 처리: Supabase가 401 반환 시 (JWT 만료) 로그아웃 + `/login` redirect

### Crawl Overwrite Protection

MVP Known Limitation: 크롤러는 매 크롤 시 description을 반환하므로,
수동 편집한 description이 다음 크롤에서 덮어써질 수 있다.

MVP 대응: 수동 편집 시 `manual_description` boolean 컬럼을 true로 설정.
`upsertTournament`에서 `manual_description == true`이면 description update skip.

```sql
-- 마이그레이션
ALTER TABLE tournaments ADD COLUMN manual_description boolean NOT NULL DEFAULT false;
```

```typescript
// upsertTournament 수정
if (t.description !== undefined && !existing.manual_description) {
  updatePayload.description = t.description ?? null;
}
```

## File Changes

### New Files (4)

| File | Role |
|------|------|
| `app/lib/services/notifications_web.dart` | FCM no-op stub for web |
| `app/lib/screens/admin/admin_shell.dart` | Sidebar + TopBar layout |
| `app/lib/screens/admin/no_access_screen.dart` | Non-admin web access notice |
| `app/lib/screens/admin/tournament_edit_screen.dart` | Tournament manual edit |

### Modified Files (3)

| File | Change |
|------|--------|
| `app/lib/main.dart` | notifications conditional import |
| `app/lib/router.dart` | Web/app route branching, /admin/* subroutes, /no-access |
| `app/lib/screens/admin/admin_screen.dart` | Extract tab widgets for reuse in AdminShell |

### DB Migration (1)

| File | Change |
|------|--------|
| `supabase/migrations/042_manual_description.sql` | `manual_description` boolean 컬럼 추가 |

### Backend (1)

| File | Change |
|------|--------|
| `supabase/functions/_shared/crawler.ts` | `upsertTournament`에서 `manual_description` 체크 |

### Unchanged

- App user flows (Bottom Nav, all existing screens)
- Existing providers

## Error Handling

- Web admin session expiry (401) -> 로그아웃 + redirect `/login`
- Tournament edit save failure (non-401) -> SnackBar error, retry possible
- CORS: Supabase Edge Functions는 기본 CORS 허용. 별도 설정 불필요.

## Dashboard Tab Content

`/admin` (대시보드)는 기존 AdminScreen의 크롤 현황 탭 위젯을 재사용한다.
신규 요약 위젯은 필요 시 추후 추가.

## Success Criteria

- `flutter build web` succeeds
- Web browser: login -> admin dashboard displayed
- Web browser: non-admin login -> no-access screen
- Mobile app: no behavioral changes (existing flows unaffected)
