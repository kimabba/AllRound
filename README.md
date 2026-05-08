<div align="center">

# 🎾 Match-up ⚽

**테니스·풋살 동호인 통합 정보 앱**

> 회원가입 시 종목·등급을 등록하면, 출전 가능한 대회만 자동으로 보여드립니다.

[![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B?logo=flutter)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Edge_Functions-3ECF8E?logo=supabase)](https://supabase.com)
[![Deno](https://img.shields.io/badge/Deno-2.1+-000000?logo=deno)](https://deno.com)
[![Gemini](https://img.shields.io/badge/Gemini-2.0_Flash-4285F4?logo=google)](https://ai.google.dev)

</div>

---

## 핵심 가치

테니스·풋살 동호인은 (1) 종목별 일반 규칙, (2) 대회별 규칙, (3) 본인 등급으로 출전 가능한 대회, (4) 최신 대회 일정 — 이 4가지를 **한 번에 확인하기 어렵습니다**.

**Match-up**은 회원가입 단계에서 종목·등급을 등록받아, 본인 등급으로 출전 가능한 대회만 홈에 자동 필터링해서 보여줍니다. 즐겨찾기·푸시 알림(D-3·신청 마감), 종목별 룰북, AI 챗봇(Gemini Search Grounding + RAG), 동호회 디렉토리가 보조합니다.

## 종목 · 등급 모델

| 종목 | enum | 표시 |
|------|------|------|
| **tennis** | `rookie` `div5` `div4` `div3` `div2` `div1` | 신입 / 5부 / 4부 / 3부 / 2부 / 1부 |
| **futsal** | `beginner` `intermediate` `advanced` | 초급 / 중급 / 고급 |

- 한 사용자가 두 종목 모두 등록 가능 (`user_sports` N:M)
- 대회의 `eligible_grades` 배열에 사용자 등급이 포함되면 출전 가능
- 종목별로 매칭하는 RPC `tournaments_for_user`가 종목 교차 매칭을 방지

## 기술 스택

```
Flutter App (iOS · Android · Web)
  ├── Supabase Auth (이메일 + 구글, 추후 카카오)
  ├── REST + SSE → Supabase Edge Functions (Deno)
  │     ├── tournaments-search/-submit/-approve   등급 자동 필터링
  │     ├── chat (SSE)                             Gemini + Search Grounding + RAG
  │     ├── semantic-search                        pgvector 의미 검색
  │     ├── embed-pending  (pg_cron 5분)
  │     ├── notify-cron    (pg_cron 1시간)         D-3 / 신청마감
  │     ├── crawl-tennis-{gwangju,jeonnam,korea}   pg_cron 일 1회
  │     ├── clubs-search · chat-history · health
  ├── Postgres + pgvector (768d HNSW)
  └── FCM 푸시
```

| 영역 | 선택 |
|------|------|
| Frontend | Flutter (Riverpod + go_router) |
| Backend | Supabase Edge Functions (Deno) — FastAPI 미사용 |
| DB | Postgres + `pgvector` + `pg_cron` + `pg_net` |
| AI 채팅 | Gemini 2.0 Flash + Google Search Grounding |
| AI 임베딩 | `gemini-embedding-001` (768차원, Matryoshka) |
| Auth | Supabase Auth |
| Push | FCM (Legacy HTTP — v1 마이그레이션 예정, [SSF-270](https://linear.app/ssfak/issue/SSF-270)) |
| Streaming | SSE (챗봇 응답) |

## 빠른 시작 (로컬 개발)

### 0. 사전 준비

- Docker Desktop
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase` 또는 `supabase-beta`)
- [Deno 2.x](https://deno.com)
- [Flutter 3.41+](https://docs.flutter.dev/get-started/install)
- [Gemini API 키](https://aistudio.google.com/apikey)

### 1. Supabase 로컬 스택 + 마이그레이션 + 시드

```bash
git clone https://github.com/kimabba/Match-up.git
cd Match-up

supabase start                  # 12개 서비스 컨테이너 기동
supabase db reset               # 마이그레이션 8개 + seed.sql 적용
```

기동 후 출력된 정보 메모:
- API: `http://127.0.0.1:54321`
- DB: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- Studio: `http://127.0.0.1:54323`
- anon key 출력값

### 2. Gemini API 키 + Edge Functions 핫리로드

```bash
mkdir -p supabase/functions
echo 'GEMINI_API_KEY=AIzaSy...본인키' > supabase/functions/.env
echo 'GEMINI_MODEL=gemini-2.0-flash' >> supabase/functions/.env

supabase functions serve --env-file ./supabase/functions/.env
```

### 3. Flutter 앱

```bash
cd app && flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<위에서 출력된 anon key>
```

### 4. 관리자 권한 부여

가입 후 자기 계정을 admin으로 승격:

```bash
docker exec -e PGPASSWORD=postgres supabase_db_matchup \
  psql -U postgres -d postgres \
  -c "update public.users set role='admin' where email='your@email.com';"
```

또는 Studio (`http://127.0.0.1:54323`) → SQL Editor에서 같은 쿼리 실행.

### 5. 검증

```bash
# 헬스체크
curl http://127.0.0.1:54321/functions/v1/health
# → {"status":"ok","service":"match-up","ts":"..."}

# 임베딩 워커 수동 트리거 (시드 13건 처리)
curl -X POST http://127.0.0.1:54321/functions/v1/embed-pending
# → {"tournaments_processed":5,"rules_processed":8,"errors":[]}

# Flutter 코드 정적 검증
cd app && flutter analyze
# → No issues found!

# Edge Functions 정적 검증
cd supabase/functions && deno lint && find . -name index.ts -exec deno check {} +
```

## API 엔드포인트

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

## 디렉토리 구조

```
Match-up/
├── app/                        Flutter 앱
│   ├── lib/
│   │   ├── main.dart · router.dart · config.dart
│   │   ├── models/ · state/ · services/ · widgets/ · utils/
│   │   └── screens/{auth, tournaments, ...}/
│   └── test/
├── supabase/
│   ├── migrations/00{1..8}_*.sql
│   ├── functions/
│   │   ├── _shared/{auth, supabase, gemini, embedding, crawler, enums, cors}.ts
│   │   └── <function-name>/index.ts × 12
│   ├── config.toml
│   └── seed.sql
├── docs/{privacy-policy.html, store-listing.md, deploy.md, reviews/}
└── README.md · CLAUDE.md
```

## 운영 작업 흐름

- 사용자 제보 → `tournaments.status='draft'` → 관리자가 `/tournaments-approve` → `published`
- 크롤러 입력 대회는 검수 없이 즉시 `published`
- 대회/룰북 내용 변경 시 트리거가 `embedding=null`로 invalidate → `embed-pending`이 5분 내 재계산
- 알림 중복 방지는 `notifications_log(user, tournament, type)` unique 인덱스
- 관리자 권한: `users.role='admin'`. RLS는 `is_admin()` SECURITY DEFINER 함수로 평가

## 프로젝트 관리

- Linear: [Match-up App (Flutter + Supabase)](https://linear.app/ssfak/project/match-up-app-flutter-supabase-8c50f8db4e20)
- 핵심 이슈: SSF-268 ~ SSF-277
- 자세한 개발 가이드: [`CLAUDE.md`](./CLAUDE.md)

## 라이선스

작성자가 별도 명시 전까지 사적 사용 한정.
