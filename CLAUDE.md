# CLAUDE.md

## Project Overview

**Match-up** — 테니스·풋살 동호인 통합 정보 앱.

회원가입 시 종목·등급을 등록하면 본인 등급으로 출전 가능한 대회만 자동 필터링되어 보여주고, 대회 즐겨찾기·푸시 알림(D-3·신청 마감), 종목별 룰북, AI 챗봇(Gemini Search Grounding + RAG), 동호회 디렉토리를 제공한다.

## Tech Stack

- **Frontend**: Flutter (Dart) — iOS / Android / 웹
- **Backend**: Supabase Edge Functions (Deno) — 모든 서버 로직 일원화. FastAPI 미사용.
- **DB**: Supabase Postgres + pgvector + pg_cron + pg_net
- **AI**: Gemini API (`gemini-2.0-flash` + Search Grounding) + `gemini-embedding-001` 768d (RAG)
- **Auth**: Supabase Auth (이메일·구글, 추후 카카오)
- **Push**: Firebase Cloud Messaging
- **Streaming**: SSE (챗봇 응답)

## Architecture

```
Flutter App
  ├── Supabase Auth (이메일 / 구글)
  ├── REST + SSE → Edge Functions (Deno)
  │     ├── tournaments-search/-submit/-approve  (등급 자동 필터링)
  │     ├── clubs-search
  │     ├── chat (SSE) — Gemini + Search Grounding + RAG
  │     ├── chat-history
  │     ├── semantic-search (pgvector)
  │     ├── embed-pending (pg_cron 5분)
  │     ├── notify-cron (pg_cron 1시간 — D-3, 마감 알림)
  │     ├── crawl-tennis-{gwangju,jeonnam,korea} (pg_cron 일 1회)
  │     └── health
  ├── Postgres
  │     ├── users / user_sports (다중 종목, 등급 enum check)
  │     ├── tournaments (+ embedding vector(768) HNSW)
  │     ├── tournament_favorites
  │     ├── clubs
  │     ├── chat_messages (영구 저장)
  │     ├── rule_articles (+ embedding vector(768) HNSW)
  │     ├── device_tokens / notifications_log
  │     └── crawl_audit
  └── FCM (앱 토큰 등록 + notify-cron 발송)
```

## 종목·등급 모델

| 종목 | 등급 enum | 표시명 |
|------|----------|--------|
| tennis | `rookie` `div5` `div4` `div3` `div2` `div1` | 신입 / 5부 / 4부 / 3부 / 2부 / 1부 |
| futsal | `beginner` `intermediate` `advanced` | 초급 / 중급 / 고급 |

- 한 사용자가 2개 종목 모두 등록 가능 (`user_sports` N:M)
- 대회 `eligible_grades` 배열에 사용자 등급이 포함되면 출전 가능
- RPC `tournaments_for_user` 가 종목별 매칭을 처리 — 단순 overlap 검색은 종목 교차 매칭이 발생할 수 있음에 주의

## Development Commands

### Supabase

```bash
# 로컬 스택 시작 (Docker 필요)
supabase start

# 마이그레이션 + 시드 적용
supabase db reset

# Edge Functions 로컬 실행
supabase functions serve --env-file ./supabase/.env.local

# 시크릿 등록 (운영 배포 시)
supabase secrets set GEMINI_API_KEY=...
supabase secrets set FCM_SERVER_KEY=...

# 함수 배포
supabase functions deploy chat tournaments-search ...
```

### Flutter

```bash
cd app/
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>

flutter analyze
flutter test
```

## API Endpoints (Edge Functions)

| Method | Path | Auth | 설명 |
|--------|------|------|------|
| GET | `/tournaments-search` | user | 등급 자동 필터링 + 텍스트 검색 |
| POST | `/tournaments-submit` | user | 사용자 제보 (status=draft) |
| POST | `/tournaments-approve` | admin | 제보 승인/거부 |
| GET | `/clubs-search` | user | 클럽 디렉토리 |
| POST | `/chat` | user | SSE 챗봇 (RAG + Search Grounding) |
| GET/DELETE | `/chat-history` | user | 대화 이력 |
| POST | `/semantic-search` | user | pgvector 의미 검색 |
| POST | `/embed-pending` | cron | 임베딩 워커 (verify_jwt=false) |
| POST | `/notify-cron` | cron | 알림 워커 (verify_jwt=false) |
| POST | `/crawl-tennis-*` | cron | 테니스 크롤러 (verify_jwt=false) |
| GET | `/health` | none | 헬스체크 |

## Key Files

### Supabase
- `supabase/migrations/00{1..8}_*.sql` — 스키마 + RLS + RPC + cron
- `supabase/functions/_shared/{gemini,embedding,supabase,auth,enums,cors,crawler}.ts`
- `supabase/functions/<name>/index.ts`
- `supabase/seed.sql` — 룰북·클럽 시드 데이터

### Flutter
- `app/lib/main.dart` — Supabase init + FCM + ProviderScope
- `app/lib/router.dart` — go_router (인증 가드, 온보딩 강제)
- `app/lib/state/providers.dart` — Riverpod (auth, user_sports, favorites, home tournaments)
- `app/lib/services/api.dart` — Edge Functions REST + SSE
- `app/lib/services/notifications.dart` — FCM 토큰 등록
- `app/lib/screens/` — auth, home, tournaments, clubs, rules, chat, profile
- `app/lib/widgets/tournament_card.dart`
- `app/lib/utils/grade_labels.dart`

## Environment Variables

### Edge Functions (Supabase Secrets)
```
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.0-flash
SUPABASE_URL=                    # 자동 주입
SUPABASE_ANON_KEY=               # 자동 주입
SUPABASE_SERVICE_ROLE_KEY=       # 자동 주입
FCM_SERVER_KEY=                  # 푸시 발송 (선택)
CRAWL_TENNIS_GWANGJU_URL=        # 크롤러 대상 URL (선택)
CRAWL_TENNIS_JEONNAM_URL=
CRAWL_TENNIS_KOREA_URL=
```

### DB GUC (cron → Edge Function 트리거용)
```sql
alter database postgres set app.cron_invoke_url = 'https://<project>.functions.supabase.co';
alter database postgres set app.cron_invoke_key = '<service-role-jwt>';
```

### Flutter (--dart-define)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
API_BASE_URL=                   # 선택 (기본: $SUPABASE_URL/functions/v1)
GOOGLE_WEB_CLIENT_ID=           # 선택
GOOGLE_IOS_CLIENT_ID=           # 선택
```

## Operational Notes

- 대회 제보 → `tournaments.status='draft'` → 관리자가 `/tournaments-approve` 로 `published` 전환
- 크롤러 입력 대회는 검수 없이 즉시 `published`
- 대회 내용 변경 시 트리거가 `embedding=null` 로 invalidate → `embed-pending` 워커가 재계산
- 알림 중복 방지는 `notifications_log(user, tournament, type)` unique 인덱스
- 관리자 권한: `users.role='admin'`. RLS는 `is_admin()` SECURITY DEFINER 함수로 판별
- 카카오 로그인은 Supabase 표준 OAuth 미지원이므로 추후 별도 Edge Function + `signInWithIdToken` 패턴으로 추가
