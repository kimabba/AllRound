# 종합 코드 리뷰 보고서

생성: 2026-05-08
범위: Match-up MVP commit `a232c18`
검토자: Senior Code Reviewer (superpowers:code-reviewer)

## 요약

- **전반적 품질**: ★★★★☆ — MVP 수준에서 일관성·구조 우수. plan에 명시된 핵심 결정사항 16개 중 15개가 구현됨.
- **plan 일치도**: 15 / 16 (카카오 OAuth 1건만 placeholder)
- **즉시 조치 필요(Blocking)**: 4건
- **중요(Should-fix)**: 6건
- **권고(Nice-to-have)**: 5건
- **MVP 출시 가능성**: B-01~B-04 처리 후 가능. 특히 B-01(임베딩 모델 불일치), B-02(라우터 redirect 가드 결함)는 출시 전 필수.

---

## 1. plan 일치도 점검

| # | plan 결정사항 | 구현 위치 | 상태 |
|---|---|---|---|
| 1 | 다 지우고 처음부터 | git history · 디렉토리 구조 | OK |
| 2 | 등급 기반 자동 필터링 | `tournaments_for_user` RPC, `homeTournamentsProvider` | OK |
| 3 | 다중 종목 N:M | `user_sports` PK `(user_id, sport)` | OK |
| 4 | 표준 enum | `enums.ts` · `grade_labels.dart` · 002 check | OK |
| 5 | 테니스 크롤링 자동화 | `crawl-tennis-{gwangju,jeonnam,korea}` + cron | OK (단, B-03 참조) |
| 6 | 풋살 수동 + 사용자 제보 | `tournaments-submit` + RLS draft | OK |
| 7 | 룰북 별도 화면 + AI 보조 | `rules_screen.dart` + `rules_semantic_search` RPC | OK |
| 8 | 클럽 디렉토리만 | `clubs` 테이블 + `clubs-search` | OK |
| 9 | Gemini + Search Grounding | `gemini.ts` `tools: [{googleSearch:{}}]` | OK |
| 10 | 이메일 + 구글 + 카카오 | login_screen — 카카오는 비활성 | **부분** (예상됨 — 추후 처리) |
| 11 | 즐겨찾기 + 푸시(D-3, 마감) | `notify-cron` + `notifications_log` unique | OK |
| 12 | 챗봇 이력 영구 저장 | `chat_messages` + chat에서 insert | OK |
| 13 | 관리자 = role + RLS | `is_admin()` SECURITY DEFINER + 정책 | OK |
| 14 | Supabase Edge Functions 일원화 | `supabase/functions/*` | OK |
| 15 | pgvector RAG | `tournaments_semantic_search` · `rules_semantic_search` | OK |
| 16 | **Gemini text-embedding-004 (768d)** | **`embedding.ts`는 `gemini-embedding-001` 사용** | **불일치 — B-01 참조** |

---

## 2. 즉시 조치 필요 (Blocking)

### [REV-B-01] 임베딩 모델이 plan 결정사항과 다름 — 문서/코드 정합성

- **위치**: `supabase/functions/_shared/embedding.ts:10`, `CLAUDE.md:14`, plan #16
- **문제**:
  - plan 16번과 `CLAUDE.md`는 **`text-embedding-004`** (768d)을 명시
  - 실제 코드는 `gemini-embedding-001`을 사용하고 768d Matryoshka 출력으로 다운프로젝션 (`README.md`만 이를 반영)
  - 두 모델은 임베딩 공간이 호환되지 않음. seed로 채워진 임베딩과 사용자 쿼리 임베딩이 동일한 모델로 생성되지 않으면 검색 품질이 무의미해짐 (현재는 우연히 둘 다 같은 코드 경로라 일관성은 유지)
  - 실제 위험: plan/CLAUDE를 따라 `text-embedding-004`로 환경변수를 바꾸려는 운영자가 있으면, `outputDimensionality` 파라미터를 `text-embedding-004`가 받지 않아 768d 보장이 깨질 수 있음 (`text-embedding-004`는 항상 768d이지만 파라미터는 무시됨)
- **권장**:
  1. plan/CLAUDE.md의 모델명을 `gemini-embedding-001`로 통일하고 768d Matryoshka라고 명시 (가장 간단)
  2. 또는 `embedding.ts` 기본값을 `text-embedding-004`로 변경 — 단, 이 경우 `outputDimensionality` 코드 분기 필요
  3. 환경변수 주석에 "모델 변경 시 기존 임베딩 전체 재계산 필요"를 추가
- **영향**: 운영 혼선. 사용자 영향은 즉각 없지만 후속 리뷰어/배포자가 잘못 이해할 가능성 큼.

### [REV-B-02] 라우터 redirect의 데드 코드 — 온보딩 강제 가드가 동작하지 않음

- **위치**: `app/lib/router.dart:30-34`
- **문제**:
  ```dart
  final sports = ref.read(userSportsProvider).valueOrNull;
  if ((sports == null || sports.isEmpty) && loc != '/onboarding') {
    if (sports != null && sports.isEmpty) return '/onboarding';
  }
  ```
  외부 `if` 조건이 `(sports == null || sports.isEmpty)`인데 내부에서는 `sports != null && sports.isEmpty`만 redirect. `sports == null`(=AsyncValue가 아직 데이터 없음/loading) 분기는 외부 if를 통과하지만 내부 if에서 빠져나와 결과적으로 redirect 없음. 의도 주석은 "로딩 중이면 보내지 않음"인데 외부 if 자체가 불필요하고 헷갈림. 더 큰 문제는 **`sports`가 `null`이지만 실제 사용자가 종목 미등록일 때**(첫 로그인 직후 FutureProvider 초기 상태) 잠깐 `/`로 진입한 뒤 데이터 로드 후 redirect가 필요한데, `redirect`는 `userSportsProvider`가 갱신될 때 `GoRouterRefreshStream`이 호출돼 다시 평가되긴 함 → 동작은 하지만 코드 의도가 모호.
  진짜 결함: `homeTournamentsProvider`가 `userSportsProvider`보다 먼저 트리거되어 빈 리스트를 보여주고, 그제서야 redirect가 일어나 `/onboarding`으로 가는 점프 깜빡임이 발생.
- **권장**:
  ```dart
  final sportsAsync = ref.read(userSportsProvider);
  // 로딩 중이면 redirect 보류
  if (sportsAsync.isLoading) return null;
  final sports = sportsAsync.valueOrNull ?? const [];
  if (sports.isEmpty && loc != '/onboarding') return '/onboarding';
  ```
- **영향**: 신규 가입자 첫 진입 UX 저하 + 코드 유지보수 시 잘못 읽기 쉬움.

### [REV-B-03] 크롤러가 published 상태로 즉시 게시 — RLS 우회 + 사이트 셀렉터 깨질 위험

- **위치**: `supabase/functions/_shared/crawler.ts:117`, `crawl-tennis-{gwangju,jeonnam,korea}/index.ts`
- **문제**:
  - 크롤러는 `service_role` 클라이언트로 동작하면서 `status: 'published'`로 즉시 입력. plan #6 ("크롤러 입력 대회는 검수 없이 즉시 published")은 의도된 결정이지만, **사이트 마크업이 변경되면 false positive 데이터가 사용자에게 노출**됨. 특히:
    - `extractTennisGradesFromText`가 키워드 기반이라 "1~5부 모두 환영" 같은 텍스트가 모든 등급으로 잘못 매핑될 수 있음 (실제 패턴 `"전\s*부수|모든\s*부수"`만 처리)
    - `dateMatch` 정규식이 본문 어디든 `(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})`를 첫 매치만 가져옴 → 게시일·접수기간·이벤트일이 섞여 있으면 잘못된 `start_date`가 들어감
    - `application_deadline`을 전혀 추출하지 않음 → notify-cron의 D-3 / deadline 알림 모두 작동 안 함 (가장 큰 가치 제안인 "마감 알림"이 크롤링 대회에서 절대 발화되지 않음)
- **권장**:
  1. **크롤러 입력은 `status='draft'` + `source` 표시로 들어가게 하고, 관리자가 일괄 승인하는 화면을 추가** (운영 안정화 전까지)
  2. `application_deadline` 추출 로직 추가 ("접수기간", "신청마감" 키워드 후 날짜)
  3. `crawl_audit`에 sample row를 저장해서 fail-safe 모니터링
- **영향**: D-3/마감 알림이 핵심 가치인데 크롤링된 대회에서는 발화되지 않을 가능성. 사용자에게 잘못된 등급/날짜 노출 가능.

### [REV-B-04] `tournaments-search`의 `Sport` 파라미터 검증 부재 + RPC 타입 강제

- **위치**: `supabase/functions/tournaments-search/index.ts:27,37`
- **문제**:
  - `const sport = url.searchParams.get('sport');` → `'tennis'`/`'futsal'`/`null` 외에 임의 문자열도 통과
  - PostgREST가 `sport` enum 캐스팅에서 `invalid input value for enum` 500 에러를 발생시킴 → 클라이언트에 의미 있는 메시지 없음
- **권장**:
  ```ts
  if (sport && sport !== 'tennis' && sport !== 'futsal') {
    return errorResponse('sport must be tennis or futsal');
  }
  ```
  같은 문제: `clubs-search/index.ts:22` (`.eq('sport', sport)`도 동일하게 임의 문자열 허용)
- **영향**: API 안정성 / 클라이언트 디버깅 비용.

---

## 3. 중요 (Should-fix)

### [REV-S-01] 챗봇 SSE 응답 누락 시 빈 assistant 메시지 영구 저장

- **위치**: `supabase/functions/chat/index.ts:215-260`
- **문제**: `streamChat`이 첫 청크부터 error 이벤트를 보내거나 네트워크가 즉시 끊기면 `assistantText === ''`인 채로 `chat_messages`에 insert. 다음 대화 시 `prior` 히스토리에 빈 assistant 턴이 들어가 Gemini 컨텍스트 품질이 깎임.
- **권장**: `if (assistantText.trim()) { await supabase.from('chat_messages').insert(...) }`

### [REV-S-02] `_authHeaders` 빈 anon 토큰 케이스 미처리

- **위치**: `app/lib/services/api.dart:17`
- **문제**: 토큰 없으면 `Authorization` 헤더 자체를 빼버림. Edge Function은 `requireUser`에서 401 반환. 단, **세션이 만료되었지만 곧 자동 갱신되는 idle race**에서 갑작스러운 401이 사용자에게 그대로 노출됨.
- **권장**: `currentSession?.isExpired == true`이면 `auth.refreshSession()` 후 헤더 재구성. 또는 Supabase 권장 패턴인 `_supabase.functions.invoke()` 사용 (단, SSE는 직접 fetch가 필요).

### [REV-S-03] `Promise.resolve(supabase.rpc(...))` 부주의한 타이핑

- **위치**: `supabase/functions/semantic-search/index.ts:58-79`
- **문제**: `supabase.rpc(...)`는 이미 `PostgrestBuilder`(`PromiseLike`)이므로 `Promise.resolve(...)`로 한 번 더 감싸면 builder가 즉시 실행되긴 하지만 `as Promise<RpcResult>` 강제 캐스팅으로 타입 안전성을 잃음. 결과 객체 모양은 `{data, error, ...}`로 정확하지만 `.error`만 검사하고 200 success path에 별도 검증이 없음.
- **권장**: `await supabase.rpc(...)`를 직접 사용:
  ```ts
  const tournamentsResult = (target === 'tournaments' || target === 'both')
    ? await supabase.rpc('tournaments_semantic_search', {...})
    : null;
  ```

### [REV-S-04] `notifications_log` insert 시 status='failed'도 unique idx에 걸려 재시도 불가

- **위치**: `supabase/migrations/006_notifications.sql:40`, `supabase/functions/notify-cron/index.ts:101-142`
- **문제**: `(user, tournament, type)` UNIQUE 인덱스 하나로 중복 방지. 그러나 send에 실패해 `status='failed'`로 저장된 row가 있으면 다음 cron 실행 때 `existing` check에 걸려 영원히 skip → 일시적 FCM 장애로 모든 사용자가 알림을 못 받게 됨.
- **권장**: dedup 쿼리에 `.eq('status', 'sent')` 추가, 또는 unique index를 `WHERE status = 'sent'` partial로 변경.

### [REV-S-05] FCM Legacy HTTP API 사용 — 2024년 6월 deprecation

- **위치**: `supabase/functions/notify-cron/index.ts:36-47`
- **문제**: `fcm.googleapis.com/fcm/send`는 Google이 2024-06-20 종료 발표했고 신규 키는 발급되지 않음. plan에서도 이미 인지 ("MVP 는 legacy 로 시작") 했으나 README는 `FCM (HTTP v1)`이라 표기 → 문서 모순.
- **권장**: 출시 전 v1 API + service account JSON으로 마이그레이션, 또는 README의 "HTTP v1" 표기를 "Legacy HTTP (deprecated, 마이그레이션 예정)"로 수정.

### [REV-S-06] `tournaments_for_user` RPC가 `RETURNS SETOF tournaments` — embedding 컬럼이 응답에 포함

- **위치**: `supabase/migrations/003_tournaments.sql:165`
- **문제**: `setof public.tournaments`는 모든 컬럼을 반환하므로 `vector(768)` 컬럼이 매 검색 응답에 직렬화되어 클라이언트로 전송. 한 row당 ~10KB 추가, 50건이면 ~500KB. 모바일 데이터 비용 + 직렬화 시간 손실.
- **권장**: `RETURNS TABLE(...)`로 명시적 컬럼만 반환하거나 PostgREST `select=` 매개변수 활용. 클라이언트(`searchTournaments`)는 어차피 embedding을 안 씀.

### [REV-S-07] `dart:io` 사용으로 Flutter Web 빌드 깨짐

- **위치**: `app/lib/services/api.dart:3` `import 'dart:io';`
- **문제**: README/CLAUDE는 Flutter Web 지원을 명시(`iOS · Android · Web`). 그러나 `dart:io`의 `HttpClient`/`Platform`은 web에서 사용 불가 → `flutter build web` 실패. SSE 처리 위해 의도적으로 사용했지만 web을 진짜 타겟이라면 분리 필요.
- **권장**: `package:http`의 `Client` + `streamedResponse` 또는 EventSource(web)/HttpClient(io) 조건부 import. 또는 README에서 Web 지원을 빼기.

---

## 4. 권고 사항 (Nice-to-have)

### [REV-N-01] `Sport` enum 중복 정의 — Dart `enum Sport`와 String 사이 변환

- **위치**: `app/lib/utils/grade_labels.dart:1`, `models/tournament.dart`(string), TS `enums.ts`
- **문제**: Dart 쪽은 `enum Sport { tennis, futsal }` + `String` 두 표현이 공존. `Tournament.sport`는 `String`, 화면에선 `sportFromString` 매번 변환. 불필요.
- **권장**: 한 가지로 통일 — Tournament 모델도 `Sport` enum으로 하든, 모두 String으로 하든.

### [REV-N-02] `is_admin()` SECURITY DEFINER가 search_path 비고정

- **위치**: `supabase/migrations/002_init_users_sports.sql:67-77`
- **문제**: SECURITY DEFINER 함수에 `set search_path = public` 누락 (handle_new_user, prevent_role_self_update에는 있음). PostgREST 환경에서는 보통 안전하지만 일관성 부족.
- **권장**: `set search_path = public, pg_temp` 추가.

### [REV-N-03] `tournaments-submit`이 `eligible_grades` 종목 검증만 하고 sport-grade enum 일치는 후순위 RLS에 위임

- **위치**: `tournaments-submit/index.ts:69-73`
- **문제**: 이미 코드에서 `isValidGrade`로 검증하므로 추가 위험은 없으나, DB의 `tournaments.sport`와 `eligible_grades` 사이의 무결성은 트리거나 check constraint로 강제하지 않음. 향후 다른 진입점이 생기면 mixed grade 데이터 가능.
- **권장**: 우선순위 낮음. 종합 무결성을 원하면 row-level CHECK 또는 BEFORE INSERT/UPDATE 트리거.

### [REV-N-04] `clubs-search` ILIKE 검색이 사용자 입력 이스케이프 없음

- **위치**: `clubs-search/index.ts:24`
- **문제**: `name.ilike.%${q}%,description.ilike.%${q}%` — `q`에 `%`, `_`, `,`, `(` 등이 있으면 PostgREST OR 표현식 파싱이 깨질 수 있음. 보안 익스플로잇은 RLS로 차단되지만 500 에러 가능. (보안 검토 SEC-M-01 참조)
- **권장**: `q.replace(/[(),%_]/g, '')` 또는 PostgREST의 `wfts`/`fts` 권장.

### [REV-N-05] `notifications_log` 알림 시간대 — UTC 기반 today/d+3 계산

- **위치**: `notify-cron/index.ts:56-57`
- **문제**: `today = new Date().toISOString().slice(0,10)`은 UTC. 한국 사용자에게 0-9 UTC 시각(=KST 9-18시)에 cron이 돌아가면 KST 기준 오늘과 일치하지 않을 수 있음. 정각 cron 24회 중 일부는 어제/오늘 경계에서 알림 누락 위험.
- **권장**: KST 변환 후 비교 또는 cron을 KST 새벽 1시에 1회만 돌려 `today=KST 오늘`로 맞춤.

---

## 5. 누락된 케이스 (정리)

| 케이스 | 처리 여부 | 메모 |
|---|---|---|
| 사용자 종목 0개 (온보딩 미완료) | OK (router redirect) | B-02 데드코드는 별개 |
| 즐겨찾기 0건 | OK (`favs.contains()`만 사용) | |
| 검색 결과 0건 (홈) | OK (홈 빈 상태 UI) | |
| 검색 결과 0건 (전체대회 화면) | OK ("결과 없음") | |
| 검색 결과 0건 (클럽) | OK | |
| 룰북 0건 | OK | |
| 챗봇 첫 진입 빈 상태 | OK (예시 메시지) | |
| 토큰 만료 | **부분** — REV-S-02 참조 | |
| SSE 중간 끊김 | **부분** — `[연결 실패]`만 표시, 재시도 없음 | |
| 동시 즐겨찾기 토글(double tap) | **위험** | upsert/delete만 호출, optimistic UI 없음. 두 번 빠르게 누르면 race로 잘못된 favorite 상태 가능 |
| 대회 제보 중복 제출 | **위험** | `_busy` 플래그 있으나 폼 키는 동일 → 빠른 더블 탭 시 race 가능 |
| 임베딩 모델 변경 후 재계산 | **누락** | embed-pending 워커는 `embedding IS NULL`만 픽업. 모델 교체 시 stale 임베딩이 그대로 남음 |
| 다국어/접근성 | **부분** | ko 단일, semantic 라벨 없음, contrast 미점검 |
| 다크모드 | **누락** | `theme:` 단일 정의, `darkTheme:` 미설정 |
| Web SSE | 동작 가능 추정 | `dart:io` HttpClient는 web에서 빌드 실패 — REV-S-07 |

---

## 6. 문서 vs 코드 불일치

| 항목 | 문서 | 실제 코드 |
|---|---|---|
| 임베딩 모델 | CLAUDE.md `text-embedding-004`, README `gemini-embedding-001` | `gemini-embedding-001` (B-01) |
| FCM API | README "HTTP v1" | Legacy HTTP API (S-05) |
| Functions 개수 | README "× 13" | 실제 12개 — README가 1개 over-count |
| Functions serve env file | CLAUDE `./supabase/.env.local` | README `./supabase/functions/.env`, 실제 파일 `supabase/functions/.env` 존재 |
| 카카오 OAuth | plan/README "추후" | login_screen에 비활성 placeholder — 일치 |
| Web 지원 | README/CLAUDE "iOS·Android·웹" | `dart:io` 사용으로 web 빌드 깨짐 (S-07) |

### 권장 문서 수정

- CLAUDE.md L14: `text-embedding-004` → `gemini-embedding-001` (또는 코드를 004로 변경)
- README L60: `FCM (HTTP v1)` → `FCM (Legacy HTTP — v1 마이그레이션 예정)`
- README L170: "× 13" → "× 12"

---

## 7. 잘된 점 (References)

- **마이그레이션 분리**가 깔끔하고 RLS·SECURITY DEFINER 패턴이 일관적임
- `tournaments_for_user` RPC가 plan의 핵심 가치(등급 자동 필터링)를 단일 SQL로 캡슐화 — 코드 추적성 우수
- Edge Functions의 `_shared/` 분리로 cors/auth/supabase/gemini 재사용성 높음
- 임베딩 invalidation 트리거가 `IS DISTINCT FROM`으로 NULL-safe하게 처리됨
- 시드 데이터가 등급 매칭 시나리오(테니스 신입~3부 / 1~2부 / 4·5부)를 골고루 커버 → E2E 테스트 가능
- `notifications_log` unique idx + `is_primary` partial unique idx 같은 정밀한 제약이 적절히 사용됨
- Riverpod의 `authStateProvider` watch로 다른 provider invalidation 패턴이 일관됨

---

## 8. 결론 + 다음 단계

### MVP 출시 가능 여부

**조건부 가능**. B-01(문서/코드 일치), B-02(라우터 가드 정정), B-04(검증) — 1시간 이내 처리 가능. B-03(크롤러 안정화)는 출시 후 모니터링 + 빠른 핫픽스 전제 시 미루는 것도 합리적. S-04(notify-cron dedup), S-05(FCM v1)은 첫 알림 발송 전 처리 필요.

### 우선 처리 순서

1. **30분**: B-01 (문서 통일), B-04 (sport 검증), N-02 (search_path), 문서 불일치 3건
2. **1-2시간**: B-02 (라우터), S-01 (빈 assistant), S-02 (토큰 갱신), S-04 (dedup status filter)
3. **반나절**: B-03 (크롤러 application_deadline 추출 + draft 모드), S-05 (FCM v1), S-07 (web SSE 분리 또는 Web 지원 제거)
4. **출시 후**: S-06 (RPC 컬럼 축소), N-01/N-03/N-04/N-05

### 후속 검토 권장 시점

- 크롤러가 운영 중인 사이트에 한 번이라도 실제 데이터를 적재한 후 (현재는 셀렉터 가설만)
- FCM v1 마이그레이션 PR 단계
- 카카오 OAuth Edge Function 추가 시 (별도 보안 리뷰 필요)

### 후속 자동화 제안

- Edge Functions에 Deno test (등급 필터링 / SSE 파싱 / `extractTennisGradesFromText`)
- Flutter widget test (`tournament_card`, 라우터 가드)
- `flutter analyze` + `deno check` CI 게이트

---

## 기존 Linear 이슈 매핑

- **B-01** (임베딩 모델 문서 불일치) — **신규** (즉시 해결 필요)
- **B-02** (라우터 redirect 데드 코드) — **신규**
- **B-03** (크롤러 안정성) — SSF-273 (풋살 크롤러)와 별개. 신규 등록 권장
- **B-04** (sport 파라미터 검증) — **신규**
- **S-01~S-04, S-06, S-07** — **신규**
- **S-05** (FCM v1) — SSF-270 범위
- **N-01~N-05** — 백로그
