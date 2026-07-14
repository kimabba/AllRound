# 시스템 아키텍처

## 스택

- **Frontend:** Flutter/Dart (iOS, Android, macOS, web)
- **Backend:** Supabase Edge Functions (Deno)
- **DB:** Supabase PostgreSQL + pgvector + pg_cron + pg_net
- **AI:** Gemini API (gemini-2.0-flash) + Search Grounding + gemini-embedding-001 (768d RAG)
- **Auth:** Supabase Auth (email/Google, Kakao 예정)
- **Push:** Firebase Cloud Messaging
- **Streaming:** SSE (챗봇 응답)

## 아키텍처 다이어그램

```
Flutter App
  ├── Supabase Auth
  ├── REST + SSE → Edge Functions (Deno)
  │     ├── tournaments-search / tournaments-submit / tournaments-approve
  │     ├── clubs-create / clubs-join / clubs-review-join / clubs-approve / clubs-search
  │     ├── chat / chat-history / semantic-search
  │     ├── embed-pending / notify-cron
  │     ├── crawl-dispatch (DB-driven 크롤러 일원화)
  │     ├── dev-auth (개발용 즉시 로그인)
  │     └── health
  ├── Postgres (→ database.md 참조)
  └── FCM
```

## Edge Function 목록

| Method | Path | Auth | 용도 |
|---|---|---|---|
| GET | `/tournaments-search` | user | 등급 기반 대회 검색 |
| POST | `/tournaments-submit` | user | 대회 제보 (status=draft) |
| POST | `/tournaments-approve` | admin | 대회 승인/거절 |
| POST | `/clubs-create` | user | 클럽 생성 요청 (status=pending) |
| POST | `/clubs-join` | user | 가입 신청/취소/탈퇴 |
| POST | `/clubs-review-join` | owner/manager | 가입 신청 승인/거절 |
| POST | `/clubs-approve` | admin | 클럽 승인/거절 |
| GET | `/clubs-search` | user | 클럽 검색 + mine=true 내 클럽 |
| POST | `/chat` | user | SSE 챗봇 (RAG + Search Grounding) |
| GET/DELETE | `/chat-history` | user | 대화 이력 |
| POST | `/semantic-search` | user | pgvector 시맨틱 검색 |
| POST | `/embed-pending` | cron | 임베딩 워커 |
| POST | `/notify-cron` | cron | D-3/마감 알림 워커 |
| POST | `/crawl-dispatch` | cron/admin | DB-driven 크롤러 통합 진입점 |
| POST | `/dev-auth` | none | 개발용 magic link 즉시 로그인 |
| GET | `/health` | none | 헬스 체크 |

## 인증 레이어 (`_shared/auth.ts`)

3단계 인증 체계:

1. **requireCronSecret** — `INTERNAL_CRON_JWT` env var 비교 (pg_cron 내부 호출)
2. **requireServiceRole** — `sb_secret_...` 형태의 Supabase secret API key 비교
3. **requireAdmin** — JWT 검증 + `users.role = 'admin'` 확인

복합 함수:
- `requireUser` — 일반 사용자 인증 (JWT → auth.getUser → users.role 조회)
- `requireServiceRoleOrAdmin` — cronSecret → secret API key → admin 순서 체크

## 환경변수

### Edge Function secrets
```
GEMINI_API_KEY, GEMINI_MODEL=gemini-2.0-flash
SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (platform 주입)
SUPABASE_PUBLISHABLE_KEYS, SUPABASE_SECRET_KEYS (새 API key JSON dictionary)
INTERNAL_CRON_JWT (pg_cron 전용 랜덤 secret)
FCM_SERVER_KEY (push 발송)
```

### Flutter (`--dart-define-from-file=.env.local`)
```
SUPABASE_URL, SUPABASE_ANON_KEY
API_BASE_URL (기본: $SUPABASE_URL/functions/v1)
```

## 공유 모듈 (`_shared/`)

| 파일 | 역할 |
|---|---|
| `cors.ts` | CORS preflight, jsonResponse, errorResponse |
| `auth.ts` | 인증 레이어 (위 참조) |
| `supabase.ts` | userClient(JWT), serviceClient() |
| `enums.ts` | TENNIS_DIVISIONS, GJ_KEYWORD_TO_SUFFIX 등 부서코드 정의 |
| `crawler.ts` | extractSidoStdDivisions, upsertTournament, 크롤러 유틸 |
| `crawler/parsers/` | 사이트별 파서 모듈 |
