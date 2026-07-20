# Flutter 앱 구조

## 핵심 파일

| 파일 | 역할 |
|---|---|
| `app/lib/main.dart` | Supabase 초기화, FCM, ProviderScope |
| `app/lib/router.dart` | go_router 라우팅 + auth/onboarding 가드 + _MainShell |
| `app/lib/config.dart` | 빌드 환경변수 (dart-define) |
| `app/lib/state/providers.dart` | Riverpod 전역 상태 |
| `app/lib/services/api.dart` | Edge Function REST/SSE 클라이언트 |
| `app/lib/models/tournament.dart` | Tournament, Club, Region, UserSport, UserTennisOrg 등 |
| `app/lib/utils/grade_labels.dart` | 부서코드·등급 레이블 + 테니스 협회 정의 |

## 내비게이션 (바텀탭 4개 + 전역 AI)

| 탭 | 경로 | 화면 |
|---|---|---|
| 오늘 | `/` | HomeScreen |
| 대회 | `/tournaments` | TournamentsScreen |
| 클럽 | `/clubs` | ClubsScreen |
| MY | `/profile` | ProfileScreen |

일반 사용자 화면에서는 바텀탭 위에 `AI에게 물어보기` 진입창을 표시한다. 진입창은 `GlobalChatDock`이 현재 경로에 맞는 추천 질문을 구성하고, `ChatScreen(embedded: true)`를 절반 높이 바텀시트로 연다. `/chat`은 바텀시트의 전체 화면 확장 경로로 유지한다. 대회·클럽 엔티티 ID는 사용자가 연결 토글을 켠 경우에만 `selectedEntity`로 전송한다.

독립 화면: `/rules`, `/notifications`, `/favorites`, `/blocked-users`, `/more`

실제 계정별 일정 데이터가 없는 친구 일정 콘셉트는 출시 라우트에서 제외하고
반응형 위젯 프리뷰로만 보존한다. 통합 캘린더 범위가 승인된 뒤 서버 권한 경계와
함께 다시 연결한다.

`/more`에서 MY, 관심 목록, 차단 관리, 룰북, 이용약관, 개인정보 처리방침으로 진입한다. `/speed-gun`은 모바일 실험 경로로 유지되며 현재 기본 메뉴에는 노출하지 않는다. 웹 어드민은 `/admin` 하위의 별도 셸을 사용한다.

## 사용자 디자인 프리뷰

`USER_DESIGN_PREVIEW=true`로 웹 앱을 실행하면 인증 없이 사용자 라우트를 점검할 수 있다. 앱 본문은 최대 390px 모바일 폭으로 표시되고 주소의 사용자 경로를 시작 라우트로 사용한다. 홈·대회·클럽·룰북과 주요 MY 보조 화면에는 로컬 프리뷰 데이터가 제공된다. 이 플래그는 릴리스 빌드에서 허용되지 않는다.

## 종목 스왑 (dev 기능)
- `_MainShell` 상단에 테니스↔풋살 SegmentedButton
- `sportOverrideProvider`로 `activeSportProvider` 수동 오버라이드
- 전환 시 대회·클럽 등 모든 종목 필터 즉시 반영

## Riverpod 상태

| Provider | 타입 | 설명 |
|---|---|---|
| `supabaseProvider` | Provider | SupabaseClient 싱글턴 |
| `apiProvider` | Provider | ApiService 싱글턴 |
| `authStateProvider` | StreamProvider | 인증 상태 스트림 |
| `currentUserProvider` | Provider | 현재 로그인 유저 |
| `userSportsProvider` | FutureProvider | 사용자 종목·등급 목록 |
| `userTennisOrgsProvider` | FutureProvider | 테니스 협회 등록 |
| `activeSportProvider` | Provider | 현재 활성 종목 (override 가능) |
| `sportOverrideProvider` | StateProvider | 수동 종목 오버라이드 |
| `homeTournamentsProvider` | FutureProvider | 홈 대회 목록 |
| `isAdminProvider` | FutureProvider | 어드민 여부 |
| `favoriteIdsProvider` | FutureProvider | 즐겨찾기 ID 집합 |
| `regionsProvider` | FutureProvider | 권역 목록 |

## ApiService 주요 메서드

### 대회
- `searchTournaments()`, `submitTournament()`, `approveTournament()`
- `tournamentReviewQueue()`, `bulkApproveTournaments()`, `bulkRejectTournaments()`
- 월 캘린더와 날짜별 대회 목록을 한 화면에서 제공
- 상세 화면을 열면 사용자별 최근 본 대회를 기기에 최대 10개 저장
- 관심 대회는 `notify-cron`이 신청 마감일과 대회 D-3 알림을 만들며, 알림 탭 시 해당 대회 상세로 이동

### 클럽
- `searchClubs()`, `myClubs()`, `createClub()`
- `joinClub()`, `cancelJoinClub()`, `leaveClub()`
- `pendingJoinRequests()`, `reviewJoinRequest()`
- `pendingClubs()`, `approveClub()` (admin)

### 사용자
- `myUserSports()`, `saveUserSports()`
- `myTennisOrgs()`, `saveTennisOrgs()`, `upsertTennisOrg()`, `deleteTennisOrg()`
- `toggleFavorite()`, `myFavoriteIds()`

### 챗봇
- `chat()` — SSE 스트림 반환

### 어드민
- `crawlAuditLogs()`, `crawlSources()`, `runCrawlSource()`

## 로그인 흐름
1. 이메일 신규 가입은 생년월일을 먼저 선택하고 `birth_date` metadata와 함께 요청
2. Before User Created Auth Hook이 누락·잘못된 날짜·만 14세 미만을 `auth.users` 생성 전에 거부
3. Google은 기존 AllRound 계정 로그인만 허용하고, 신규 사용자는 이메일 가입으로 안내
4. 가입 트리거가 검증된 생년월일을 `public.users.birth_date`에 즉시 저장
5. 로그인 후 user_sports 미등록이면 `/onboarding`으로 리다이렉트
6. (개발용) Dev 어드민 로그인: dev-auth Edge Function → magic link 토큰 → verifyOTP
