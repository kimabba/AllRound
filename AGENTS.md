# AGENTS.md — Match-up Agent Router

This file is intentionally short. Do **not** turn it into a full project manual.
Detailed rules live under `docs/rules/` and should be loaded only when the task touches that area.

## 🚨 작업 시작 전 필독

**모든 작업(사람·AI) 시작 전 [`docs/team/START-HERE.md`](docs/team/START-HERE.md)를 먼저 읽는다** — 역할(드론/시리/백과장/kimabba)·레인(파일 충돌 방지)·2주 출시 로드맵·절대 주의사항. 매 세션 첫 행동.

## Always-on rules

1. Preserve user work. Check the working tree before broad edits and never overwrite unrelated changes.
2. Keep commits/changes small: one change should have one purpose.
3. Server/DB are the source of truth for auth, eligibility, visibility, quotas, and admin decisions.
4. Type safety is mandatory:
   - TypeScript/Deno: no `any`; parse external JSON as `unknown` and narrow with type guards.
   - Dart/Flutter: avoid `dynamic` except JSON boundaries; convert immediately to typed models.
   - SQL: new tables require explicit types, RLS enabled, and policies.
5. Root rule files stay small. Add detailed guidance under `docs/rules/`, then add a link here if needed.
6. Before finalizing, run the checks relevant to the files changed, or state exactly why they were not run.

## Loop prevention

- 같은 파일 조사나 같은 계획을 두 번 반복하지 않는다.
- 컨텍스트 압축 후 작업을 처음부터 재시작하지 않는다.
- 압축 후에는 `git status`와 `git diff`로 현재 결과부터 확인한다.
- 동일한 차단 상태가 두 번 반복되면 작업을 중단하고 사용자에게 보고한다.
- 사용자가 이미 진단 완료라고 명시한 원인은 재조사하지 않는다.
- 요청 범위 밖의 후속 기능은 구현하지 않는다.

## Load-on-demand rule map

Read only the docs needed for the task:

| Task touches... | Load first |
|---|---|
| Project overview, API map, env, operations | `docs/rules/PROJECT_CONTEXT.md` |
| Coding style, PR gates, language rules | `docs/rules/CODING_RULES.md` |
| Tournaments, sports, grades, eligibility, clubs | `docs/rules/DOMAIN_RULES.md` |
| Flutter app, routing, UI, Riverpod, API client | `docs/rules/FRONTEND_RULES.md` |
| Supabase Edge Functions, Deno, Gemini, SSE | `docs/rules/BACKEND_RULES.md` |
| Migrations, RLS, RPC, pgvector, cron | `docs/rules/DATABASE_RULES.md` |
| Auth, secrets, RAG safety, rate limits, abuse controls | `docs/rules/SECURITY_RULES.md` |
| Speed-gun/video/ball tracking logic | `docs/rules/SPEED_GUN_RULES.md` |
| Harness scripts, CI, custom rule checks | `docs/rules/HARNESS.md` |

## Knowledge base (현재 상태 문서)

프로젝트의 현재 상태를 파악하려면 `docs/kb/` 참조:

| 문서 | 내용 |
|---|---|
| `docs/kb/architecture.md` | 시스템 아키텍처, Edge Function 목록, 인증 |
| `docs/kb/database.md` | 전체 DB 스키마, RLS, 트리거 |
| `docs/kb/clubs.md` | 클럽 관리 워크플로우 |
| `docs/kb/domain-tennis.md` | 테니스 협회·부서코드 체계 |
| `docs/kb/domain-futsal.md` | 풋살 도메인 |
| `docs/kb/crawler.md` | 크롤러 시스템 |
| `docs/kb/flutter-app.md` | Flutter 앱 구조·상태관리 |
| `docs/kb/ai-chat.md` | AI 챗봇·RAG 시스템 |

## Common checks

Run the smallest relevant set, or use the common harness:

```bash
# Common repo harness
scripts/harness/run_all.sh

# Flutter changes
cd app && flutter analyze && flutter test

# Edge Function changes
cd supabase/functions && deno fmt --check */index.ts _shared/*.ts tests/*.ts && deno lint --config deno.json */index.ts _shared/*.ts tests/*.ts && deno check --config deno.json */index.ts _shared/*.ts tests/*.ts && deno test --config deno.json --allow-env --allow-read tests

# DB migration changes
supabase db reset
```
