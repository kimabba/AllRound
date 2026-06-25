<div align="center">

# 올라운드 (AllRound)

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

**올라운드**은 회원가입 단계에서 종목·등급을 등록받아, 본인 등급으로 출전 가능한 대회만 홈에 자동 필터링해서 보여줍니다. 즐겨찾기·푸시 알림(D-3·신청 마감), 종목별 룰북, AI 챗봇(Gemini Search Grounding + RAG), 동호회 디렉토리, **스피드건**(모바일 전용, 비디오 분석)이 보조합니다.

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
  │     └── clubs-search · chat-history · health
  ├── Postgres + pgvector (768d HNSW)
  └── FCM 푸시
```

| 영역 | 선택 |
|------|------|
| Frontend | Flutter (Riverpod + go_router) |
| Backend | Supabase Edge Functions (Deno) |
| DB | Postgres + `pgvector` + `pg_cron` + `pg_net` |
| AI 채팅 | Gemini 2.0 Flash + Google Search Grounding |
| AI 임베딩 | `gemini-embedding-001` (768차원, Matryoshka) |
| Auth | Supabase Auth |
| Push | FCM |
| Streaming | SSE (챗봇 응답) |

---

## 빠른 시작 (로컬 개발)

### 사전 준비 (최초 1회)

- Docker Desktop
- [Supabase CLI](https://supabase.com/docs/guides/cli) — `brew install supabase/tap/supabase`
- [Deno 2.x](https://deno.com)
- [Flutter 3.41+](https://docs.flutter.dev/get-started/install)
- [Gemini API 키](https://aistudio.google.com/apikey)

### 1단계 — 환경 파일 준비 (최초 1회)

```bash
# Flutter 앱 환경변수 (JSON 형식)
cp app/.env.local.example app/.env.local

# Edge Functions 환경변수
cp supabase/functions/.env.example supabase/functions/.env
# → GEMINI_API_KEY 값 채우기
```

### 2단계 — Supabase 로컬 스택 기동 (최초 1회)

```bash
make setup
```

출력된 **anon key** 를 `app/.env.local` 의 `SUPABASE_ANON_KEY` 에 붙여넣기.

### 3단계 — 매일 개발 (터미널 2개)

```bash
# 터미널 1 — 백엔드 (Edge Functions 핫리로드)
make backend

# 터미널 2 — Flutter 앱
make app
```

### 검증

```bash
make check    # flutter analyze + deno lint

curl http://127.0.0.1:54321/functions/v1/health
# → {"status":"ok","service":"match-up","ts":"..."}
```

### 관리자 권한 부여

Supabase Studio (`http://127.0.0.1:54323`) → SQL Editor:

```sql
update public.users set role='admin' where email='your@email.com';
```

---

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

---

## 디렉토리 구조

```
올라운드/
├── Makefile                        로컬 개발 명령어 (setup / backend / app / check)
├── app/                            Flutter 앱
│   ├── .env.local.example          환경변수 템플릿 (JSON, --dart-define-from-file 용)
│   ├── lib/
│   │   ├── main.dart · router.dart · config.dart
│   │   ├── models/ · state/ · services/ · widgets/ · utils/
│   │   └── screens/{auth, tournaments, speed_gun, ...}/
│   └── test/
├── supabase/
│   ├── migrations/001~009_*.sql    스키마 · RLS · RPC · cron
│   ├── functions/
│   │   ├── .env.example            Edge Function 환경변수 템플릿
│   │   ├── _shared/                공용 Deno 헬퍼
│   │   └── <function>/index.ts     × 13개
│   ├── config.toml
│   └── seed.sql
├── docs/
│   ├── rules/                      개발 규칙 (load-on-demand)
│   └── plans/ · reviews/ · research/
├── scripts/harness/                정적 검증 스크립트
├── AGENTS.md                       룰 파일 로드 맵
└── CLAUDE.md                       AI 코딩 지침
```

---

## 운영 작업 흐름

- 사용자 제보 → `tournaments.status='draft'` → 관리자가 `/tournaments-approve` → `published`
- 크롤러 입력 대회는 검수 없이 즉시 `published`
- 대회/룰북 내용 변경 시 트리거가 `embedding=null`로 invalidate → `embed-pending`이 5분 내 재계산
- 알림 중복 방지는 `notifications_log(user, tournament, type)` unique 인덱스
- 관리자 권한: `users.role='admin'`. RLS는 `is_admin()` SECURITY DEFINER 함수로 평가

## 프로젝트 관리

- Linear: [올라운드 App (Flutter + Supabase)](https://linear.app/ssfak/project/match-up-app-flutter-supabase-8c50f8db4e20)

## 라이선스

작성자가 별도 명시 전까지 사적 사용 한정.
