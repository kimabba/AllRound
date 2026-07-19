# 대회 요강 AI 정형화 파이프라인 — 인수인계 (HANDOFF)

작성: 2026-07-18 · 브랜치 `feat/tournament-regulation-ai-formatting` · **PR #244** (https://github.com/kimabba/AllRound/pull/244) · Linear **JY-137**

다른 환경에서 이어받는 방법: `git fetch && git checkout feat/tournament-regulation-ai-formatting` (HEAD = `f43e679`).

---

## 1. 지금 어디까지 됐나 (요약)

원문 → **Gemini 정형화** → 검수 스테이징 파이프라인을 **구현 완료하고 프로덕션에 이미 라이브**로 올렸다. PR #244로 repo에 반영됨(CI 5체크 통과). 코드/DB 모두 done, 남은 건 **머지 + 어드민 검수 + follow-up**뿐.

- 설계 스펙: `docs/superpowers/specs/2026-07-17-tournament-regulation-ai-formatting-design.md`
- 구현 계획: `docs/superpowers/plans/2026-07-17-tournament-format-pipeline-{db,crawler,edge,embedding,admin-ui}.md`
- 배경 감사: KATO DROPPED-TEXT / gnuboard TRUNCATED·GENUINE-THIN / 풋살 무손실

## 2. 구현된 것 (5 서브시스템, subagent-driven TDD로 20 task)

1. **DB** (`supabase/migrations/20260717163946_tournament_format_pipeline.sql`, `..._format_staged_rpc.sql`, `..._guard_exclude_revision.sql`): 상태/lease 컬럼, 트리거(revision bump / format_* 변조차단), RPC `format_pending_claim/complete/reject/fail` + `format_apply_staged/reject_staged`, 백필. **프로덕션 적용·마이그레이션 히스토리 기록 완료.**
2. **크롤러** (`_shared/crawler.ts` + gnuboard/kato 파서): 파서는 요강/description/prize/format 미방출(undefined), 크롤러가 값 보존·재크롤 hash 재큐·rawHtml 없으면 skipped.
3. **format-pending Edge** (`format-pending/index.ts`, `logic.ts`, `_shared/gemini.ts generateStructured`): claim→본문추출→Gemini 구조화→검증(민감값 개별 숫자런 매칭+마스킹, 문의처/전화 제외)→complete/reject/fail. **배포됨, pg_cron `2-59/5` 가동.**
4. **임베딩** (`embed-pending/index.ts`): `embedding_input_revision` optimistic write, 미정형 제외. **재배포됨.**
5. **어드민 UI + 앱** (`tournament.dart` FormatStatus, `format_review_screen.dart`, `admin_api.dart`, router/shell): `/admin/format-review` 검수 화면(staged 승인/반려 + 검증실패 flags 표시).

## 3. 프로덕션 상태 (project `bsjdgwmveokanclqwtvx`, 2026-07-18 기준)

- `format_status`: needs_review 35(전부 staged) / pending 15(재큐 14 + draft 성남배 1) / skipped 31
- cron: job 9 `format-pending` (`2-59/5`), job 1 `embed-pending` (`*/5`) 활성
- **품질 검증 완료**: staged 5건 원문 대조 → 할루시 0건, 어드민 승인 가능 수준(계좌 누락·상금 뭉뚱그림만 약점)

## 4. 안전장치 (검증됨)

- **review-first**(스펙 §12, I2 결정): 기존·신규 published 모두 최초 정형화는 `format_staged`에만 → **사용자 노출 콘텐츠는 어드민 승인 전까지 무변**. 재크롤만 자동 반영.
- 마스킹: `format_flags`에 원문 계좌/전화 숫자 미포함 (`01*-****-****`)
- durable lease(claim token) + stale-write 가드 + 임베딩 revision → 중복/경합/stale 벡터 방지

## 5. 남은 작업 (우선순위)

1. **PR #244 머지** (kimabba) — CI 5체크 + Codex 리뷰 후. `gh pr merge --admin` 금지, 정상 머지.
   - ⚠️ **Base 주의**: 이 브랜치는 main 미머지 **design 커밋 3개**(`fbeff5f`/`59b684f`/`dbfa853`, 종목색·테마, 본 작업 무관) 위에 있음 → PR diff에 포함. 먼저 main 반영할지 함께 머지할지 판단 필요.
2. **재큐 14건 재정형화 확인** — 다음 cron 후 `select format_status,count(*) from tournaments group by 1` 로 needs_review(staged)로 잘 갔는지, 문의처 과탐 재발 안 하는지 확인.
3. **어드민 검수** — `/admin/format-review`에서 staged 35건 원문 대조 승인. 승인 시 `format_apply_staged`로 콘텐츠 반영.
4. **Follow-up (JY-137, 출시 후 DB 재점검)**:
   - 정형화 프롬프트에 **입금계좌 필수 필드** 명시 + 상금 구체화 (`format-pending/index.ts` buildPrompt) → 재정형화
   - `CONTACT_LABEL` 라벨 확장(모델이 "안내" 등으로 라벨하면 우회) — `logic.ts`
   - `_shared/crawler/parsers/`가 CI lint glob 미포함 (latent)
   - staged `regulation_notes: []` → `array_agg`→NULL 정규화 (`format_apply_staged`)
   - `format_flags` 어드민 UI 상세 표시, apply/reject 반환값 미체크
   - regulation_* jsonb vs 별도 테이블, crawl_documents raw_html 보존정책, closed 임베딩 정책

## 6. 재확인/운영 명령

```bash
# CI 상태
gh pr checks 244
# 정형화 진행 (Supabase MCP execute_sql, project bsjdgwmveokanclqwtvx)
select format_status, count(*) filter (where format_staged is not null) staged,
  count(*) filter (where format_flags is not null) flags, count(*) from tournaments group by 1;
# 강제 재정형화(특정 행): guard 트리거 disable/enable로 감싸 format_status='pending', format_attempts=0, format_flags=null
# Edge 배포
supabase functions deploy format-pending --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json
```

## 7. 커밋 맵 (origin/main..HEAD, 본 작업 = c59b80c 이후)

- `9c80ce3` 스펙 / `c59b80c` 계획 5개
- DB: `740dfb6`→`c94962e` (Plan1 Task1~8) + `3f1c929`(staged RPC) + `4c15ad0`(guard revision 제외)
- 크롤러: `e056792`(가드) `e489390`(gnuboard) `c17799b`(kato)
- Edge: `5a54cc2`(gemini) `fd0bf55`→`c00ceb6`(logic+검증fix) `2885767`(index) `1a579f4`(배포/cron) `f43e679`(문의처 과탐 제외)
- 임베딩: `e08df65` `f5ccfa5`
- 앱/어드민: `564ff22`(enum) `23e69b8`(화면) `d27fc6b`(검수큐 flags)
- 스펙 갱신: `cd2f480`(review-first)
- (base) design 커밋 `fbeff5f`/`59b684f`/`dbfa853` — 본 작업 아님
