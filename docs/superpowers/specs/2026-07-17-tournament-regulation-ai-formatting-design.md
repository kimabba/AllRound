# 대회 요강 AI 정형화 파이프라인 — 설계 스펙

작성일: 2026-07-17 · 대상: `bsjdgwmveokanclqwtvx` · 관련 Linear: JY-137(출시 후 DB 재점검)

설계 근거: 원격 DB 실측(Fable DB 전문가) + Codex(gpt-5.6-terra, xhigh) 어드버서리얼 리뷰 반영. Codex 판정 N(초안)의 P0 4건·P1 10건을 본 스펙에 모두 반영해 해소한다.

---

## 1. 배경 · 문제

전 대회(75건) 요강 표시 품질을 Fable 에이전트 6개로 원문 대조 감사한 결과, 소스별로 원인이 상이:

| 소스 | 상태 | 원인 |
|---|---|---|
| KATO (kato.kr) 9건 | 🔴 DROPPED-TEXT | 원문에 요강(계좌·상금·환불·유의사항·경기방식·자격)이 **텍스트로 존재하는데 파서가 통째로 버림**. 메타라인만 저장 |
| gnuboard 지난대회 | 🟠 TRUNCATED | 원문 요강 5,800~19,000자인데 파서의 2000자 하드컷에 걸려 11~38%만 저장. 컷 지점이 참가자격 직전 |
| gnuboard 예정대회 12건 | ⚪ GENUINE-THIN | 원문 신청페이지에 요강 미게시("부서추후공지"). 파서 무결 |
| 풋살(amfutsalhub) | ⚪ 무손실 | description 6/6 무손실. 요강이 포스터 이미지에만 있는 구조적 한계 |

**핵심**: 대회마다 요강 형식이 제각각이라 규칙기반 파싱이 한계. 원문(raw_html)은 이미 보존되므로, **LLM으로 원문 → 구조화 요강**을 뽑아 채우는 정형화 단계를 신설한다.

## 2. 목표 · 비목표

**목표**
- 파서는 기본 메타(날짜·부서·지역·제목·참가비·source_url)만 추출 + 원문 보존. 규칙기반 요강 파싱은 제거.
- 신규 Edge Function `format-pending`이 원문을 Gemini로 구조화 → `regulation_fields`/`regulation_notes`/`regulation_body`/`prize`/`format`/`description`을 채움.
- 민감값(금액·계좌·날짜) 원문 substring 검증, 실패·이상 시 `needs_review` 에스컬레이션.
- 앱은 이미 구조화 필드를 렌더하므로 표시 코드 변경 최소.

**비목표(이번 스코프 밖)**
- 포스터 이미지 OCR/AI(P6 별도). amfutsalhub 등 이미지-only 요강.
- amfutsalhub `regulation_fields` 내부 메타 정리(별도 티켓 — 결정 6).
- closed 대회 시맨틱 검색 포함(현행 published 전용 유지).

## 3. 아키텍처 · 데이터 흐름

신규 컴포넌트: Edge Function `format-pending`(기존 `embed-pending`과 대칭, service client, pg_cron 구동).

```
크롤(파서)  →  tournaments (기본 메타)          [format_status='pending' 기본]
            →  crawl_documents.raw_html (원문 보존, 기존)
                     │  (비동기, pg_cron */5분 offset)
format-pending claim(RPC) → pending→processing(lease/token) → raw_html 본문추출 → Gemini 구조화
                     → substring 검증
                        ├─ 통과 → complete RPC(콘텐츠+formatted, token/hash/doc 조건)
                        └─ 실패/이상 → needs_review(콘텐츠 미기록, flags만)
                     │  (콘텐츠 변경 → 트리거가 embedding NULL + revision++)
embed-pending  →  status='published' & embedding NULL → 재임베딩(revision optimistic write)
```

## 4. 상태 머신 (Codex P0-1 반영: durable claim)

`format_status` 전이:

```
pending ──claim──▶ processing ──complete──▶ formatted
   ▲                   │ └──validate fail──▶ needs_review
   │                   └──fail/lease expire──▶ (attempts<3 ? pending : failed)
   │
   └── (재크롤 hash 변경 시 크롤러가 pending 재설정)
skipped  ← raw_html 없음 / manual_description=true / (초기 백필 대상 아님)
needs_review ── 어드민 승인 ──▶ formatted (콘텐츠 반영)
failed ── 어드민 수동 재큐 ──▶ pending
```

**초안의 치명 결함(Codex P0-1)**: 초안 claim RPC는 `format_attempts`만 올리고 상태는 `pending` 유지 → 락 해제 즉시 다음 cron이 같은 행 재claim → **Gemini 중복 호출**, attempts 소진 시 pending인 채 고착. → `processing` 상태 + `claim_token` + `claimed_at` lease로 해소.

## 5. DB 스키마 변경 (`tournaments` 컬럼 추가)

| 컬럼 | 타입 | 기본값 | 제약 | 용도 |
|---|---|---|---|---|
| `format_status` | text | `'pending'` | CHECK IN (pending,processing,formatted,needs_review,failed,skipped) | 큐 상태 |
| `format_attempts` | smallint | `0` | CHECK ≥ 0 | 재시도 카운터 |
| `format_claim_token` | uuid | NULL | — | lease 토큰(claim 시 발급, complete/fail에서 대조) |
| `claimed_at` | timestamptz | NULL | — | lease 시작 시각(만료 회수 기준) |
| `format_document_id` | uuid | NULL | — | 정형화에 사용한 crawl_documents.id (완료 조건) |
| `format_source_hash` | text | NULL | — | 사용한 content_hash (stale-write 방지) |
| `format_model` | text | NULL | — | 사용 모델 식별자 |
| `formatted_at` | timestamptz | NULL | — | 마지막 정형화 성공 시각 |
| `format_flags` | jsonb | NULL | CHECK (NULL OR jsonb_typeof='array') | 검증 플래그(**마스킹된 값만**, §11) |
| `format_staged` | jsonb | NULL | CHECK (NULL OR jsonb_typeof='object') | 검수 스테이징 결과(published 승인 전 보관, §12) |
| `embedding_input_revision` | bigint | `0` | CHECK ≥ 0 | 임베딩 경합 방지(§7) |

- `format_status`는 **text+CHECK**(enum 아님). 근거: `ALTER TYPE ADD VALUE`는 같은 트랜잭션에서 새 값 사용 불가 → execute_sql 단일 스크립트와 충돌. 이 DB 최신 선례(`crawl_documents.parse_status`, `entry_fee_unit`)도 text+CHECK, `tennis_org`는 enum→text로 되돌린 이력. 향후 CHECK 확장은 `NOT VALID → VALIDATE → 기존 DROP` 순서(Codex P2).
- `ADD COLUMN ... DEFAULT`는 PG11+ fast default(리라이트 없음)지만 ALTER는 ACCESS EXCLUSIVE 락 → 트래픽 시간대 밖 적용(Codex P1/P2).

## 6. Claim / Complete / Fail RPC (Codex P0-1·P0-4·P1 반영)

세 개의 `security definer` RPC. **모두 `set search_path = pg_catalog, public` + 완전 수식(`public.tournaments`)**(Codex P1 hardening). 각 RPC는 `revoke execute from public, anon, authenticated` 후 **`grant execute ... to service_role` 명시**(Codex P0-4: 함수 ACL은 RLS 우회와 별개).

**`format_pending_claim(batch_size int, max_bytes int)`** — pending을 processing으로 원자 전이:
- 선별: `format_status='pending' AND manual_description=false AND format_attempts<3 AND status<>'draft'`(결정 5) `AND exists(crawl_documents)`.
- `FOR UPDATE SKIP LOCKED`, `order by created_at`.
- 원자 UPDATE: `format_status='processing'`, `format_attempts+1`, `format_claim_token=gen_random_uuid()`, `claimed_at=now()`, `format_document_id=<최신 doc id>`.
- 반환: `tournament_id, title, sport, source, format_claim_token, format_document_id, content_hash`. **raw_html은 반환하지 않음**(Codex P1: 최대 1.39MB × batch → 응답 10MB+). Edge가 doc_id로 개별 조회 + 본문추출/절단. `max_bytes` 합계로 batch 상한.
- 최신 문서 선택 `order by fetched_at desc, id desc`(Codex P2 결정성).

**`format_pending_complete(...)`** — 결과 반영. 조건(모두 만족해야 씀):
```sql
where id = $tid
  and format_status = 'processing'
  and format_claim_token = $token
  and manual_description = false
  and exists (select 1 from public.crawl_documents cd
              where cd.id = $document_id and cd.tournament_id = $tid
                and cd.content_hash = $source_hash)   -- Codex P1: stale-write 차단
```
- 검증 통과 & **신규/승인 유입**: 콘텐츠(regulation_*/prize/format/description) + `format_status='formatted'`, token/claim 클리어, `format_source_hash`, `formatted_at`.
- 검증 통과 & **기존 published 백필 대상**(결정 1): 콘텐츠 미기록, `format_staged=<결과 jsonb>` + `format_status='needs_review'`.
- 검증 실패: 콘텐츠·staged 미기록, `format_flags`(마스킹) + `format_status='needs_review'`.

**`format_pending_fail(tid, token)`** — 오류/lease 만료 회수(Codex P1): `format_attempts>=3 → failed`, else `→ pending`, token/claimed_at 클리어. 원자적.

**lease 만료 회수**: claim RPC 진입 시 `format_status='processing' AND claimed_at < now()-interval '15 min'` 행을 먼저 `format_pending_fail` 로직으로 회수.

## 7. 임베딩 경합 해결 (Codex P0-2)

**결함**: embed-pending이 옛 텍스트로 벡터 생성 중 format이 콘텐츠 갱신 → 트리거가 embedding NULL. 이후 embed의 `update.eq('id')`가 옛 벡터를 non-NULL로 덮어씀 → 트리거 미발동(embedding-only UPDATE) → **stale 벡터 영구 잔존**.

**해결**: optimistic write.
- `tournaments_invalidate_embedding` 트리거 수정: 콘텐츠 컬럼 변경 시 `embedding=NULL` + `embedding_input_revision = embedding_input_revision + 1`.
- embed-pending: select 시 `embedding_input_revision` 함께 읽고, 완료 UPDATE에 `where embedding is null and embedding_input_revision = $revision_read` 조건. revision이 바뀌었으면 쓰기 스킵(다음 사이클 재생성).
- (비용) embed-pending 선별에 `format_status <> 'pending'` 필터 추가(결정 3, 미정형 텍스트 임베딩 방지). 단 skipped/신규 유입은 임베딩 진행되도록 필터는 `not in ('pending','processing')`.

## 8. 크롤러 변경 (Codex P0-3·P1 반영) — 크롤러 PR에 반드시 포함

`supabase/functions/_shared/crawler.ts`:
1. **prize/format undefined 가드**(Codex P0-3): 현재 update 경로는 `prize: t.prize ?? null, format: t.format ?? null`을 **항상** payload에 포함 → 신규 파서가 미방출 시 AI 결과가 null로 소실. `description`/`regulation_*`처럼 `!== undefined`일 때만 payload에 넣도록 수정.
2. **정형화 책임 이관**: 규칙기반 요강 파싱 제거 후, 파서는 `description`/`prize`/`format`/`regulation_*`를 **방출하지 않음(undefined)** → upsert가 기존/AI 값 보존. `null` 방출 금지(와이프됨).
3. **재크롤 재큐**(결정 2, Codex P1): upsert 시 새 `content_hash`가 기존 `format_source_hash`와 다르면 `format_status='pending'`, `format_claim_token=NULL` 재설정. 크롤러 로직에서 명시적 처리(트리거 아님).
4. **skipped 전환**(Codex P1): insert에서 `rawHtml` 없으면 `format_status='skipped'`. `manual_description=true`로 전환되는 경로가 생기면 동일.
5. 회귀 테스트: `crawler_upsert_preserve_test.ts`에 (2)(3) 케이스 추가.

## 9. Edge Function `format-pending` 로직

1. `requireServiceRoleOrAdmin` (embed-pending과 동일 인증, cron JWT).
2. `format_pending_claim(batch, max_bytes)` 호출 → 클레임 목록.
3. 각 건: `crawl_documents`에서 raw_html 조회 → **본문 추출/절단**(네비·푸터 제거, Gemini 입력 상한, 기존 077 ≤2500자 계약 유지).
4. Gemini 구조화 호출(responseSchema로 `{regulation_fields:[{label,value}], regulation_notes:[], regulation_body, prize, format, description, confidence, unusual}`). 모델은 `_shared/gemini.ts`.
5. `normalizeRegulationFields`로 shape 검증(빈 배열이면 needs_review). regulation_body 절단.
6. **검증**(§10) → `format_pending_complete(...)` 또는 needs_review 분기.
7. 오류 시 `format_pending_fail`.

## 10. 검증 & needs_review 규칙

- LLM 프롬프트: "원문에 없는 정보 생성 금지, 불명확하면 생략, 각 값에 confidence·unusual 플래그".
- **민감값 원문 substring 대조**: 금액·계좌·날짜가 원문 raw text에 그대로 존재하는지. 미존재 → 환각 → needs_review.
- LLM `unusual=true` 또는 confidence 낮음 → needs_review.
- 상식 범위 이탈(참가비/상금 비정상, 계좌 형식) → needs_review.
- 통과분: 신규/승인 유입은 formatted 즉시, 기존 published 백필은 staged(§12).

## 11. RLS · 보안 (Codex P1 3건 반영)

1. **format_flags 공개 노출**(Codex P1): RLS는 행 단위라 published/closed 행의 새 컬럼이 anon에 노출됨. `format_flags`에 계좌번호·날짜 **원문값을 넣지 않는다** — `{code, field, masked}`만(예: `found:"1234-**-****"`). DB CHECK(array) + Edge 마스킹 + 회귀 테스트로 강제. (민감 상세가 필요해지면 admin 전용 뷰/컬럼 분리 — JY-137 후속.)
2. **draft 소유자 변조 차단**(Codex P1): `tournaments_self_draft_update`가 컬럼 무제한 → 소유자가 자기 draft의 `format_*` 위조 가능. **BEFORE UPDATE 트리거로 비-admin의 `format_*`/`embedding_input_revision` 변경 거부**. (draft는 정형화 대상서도 제외 — 결정 5.)
3. **security definer hardening**(Codex P1): 세 RPC 모두 `set search_path = pg_catalog, public` + 완전 수식 + `PUBLIC`의 public schema CREATE 권한 없음 확인.
4. format-pending은 service client(RLS 바이패스, embed-pending과 동일). raw_html은 crawl_documents(admin+service 전용)라 안전.

## 12. 백필 · 롤아웃 (결정 1: 검수 스테이징)

적용 직전 `count(distinct t.id)` 재검증 후(Codex P2) 백필:
- **skipped(31건)**: crawl_document 없음(manual-* 30 + jeonnam closed 1) 또는 manual_description=true.
- **pending(50건)**: KATO 9 + gnuboard published 19 + gnuboard closed 22.

**검수 스테이징(review-first, 2026-07-17 확정)**: format worker가 결과를 `format_staged`에 넣고 `needs_review`로 둔다(콘텐츠 미변경 → 사용자엔 기존 표시 유지). 어드민 검수 UI에서 원문 대비 승인 시 staged→실제 콘텐츠 반영 + `formatted`. 판정은 `status in (published,closed) AND formatted_at IS NULL`이며, 이는 **기존 백필 50건뿐 아니라 신규(draft 승인→published) 대회의 최초 정형화도 검수 스테이징**함을 뜻한다. 파서가 요강을 만들지 않으므로 신규 대회는 어드민 승인 전까지 요강이 빈 채로 노출되나, P0 UGC 안전을 우선해 review-first를 채택한다(whole-branch 리뷰 I2 결정). **재크롤(`formatted_at` 존재)만 검증 통과 시 자동 반영.**
- 어드민 검수 UI(간단): needs_review 목록 + staged 미리보기 + 승인/반려. (구현 계획서에서 상세.)

closed 재정형화 시 embedding NULL 후 미복구는 검색이 published 전용이라 실질 영향 없음(Codex P1은 "명시적 결정 요구" → 본 스펙에서 **closed는 검색 비대상으로 확정**, 필요 시 embed 필터 확장은 향후).

## 13. 앱 표시

변경 최소. `tournament_detail_screen.dart:297`이 이미 `regulationFields`+`regulationBody`+`regulationNotes` 렌더, 셋 다 비면 `description` 폴백. LLM이 채우면 자동으로 구조화 카드. `format_status`는 Dart union/enum으로 타입화(any/dynamic 금지). 사용자 화면에 상태 노출 없음(어드민만).

## 14. 마이그레이션 (결정 8: apply_migration)

`apply_migration`(히스토리 기록) + repo `supabase/migrations/20260717XXXXXX_tournament_format_pipeline.sql` 동일 커밋. `db push` 금지. **apply 도구의 트랜잭션 보장 확인**(Codex P1) — 미보장 시 명시적 BEGIN/COMMIT + lock/statement timeout.

순서: [1] 컬럼 추가(CHECK 포함) → [2] partial index(`WHERE format_status='pending'`) → [3] 트리거 수정(invalidate_embedding revision++, format_* 변조 차단) → [4] 백필 UPDATE(검증 후) → [5] claim/complete/fail RPC + GRANT → [6] `NOTIFY pgrst, 'reload schema'`. 롤백 스크립트 포함(콘텐츠 컬럼 불변). 적용 후 `supabase gen types` + Dart 모델 재생성.

## 15. 테스트 계획

- **RPC 동시성**: claim 병렬 호출 시 같은 행 이중 클레임 없음(processing+token). complete가 token/hash 불일치 시 no-op. fail의 attempts 전이.
- **stale-write**: claim 후 content_hash 변경 → complete 거부.
- **임베딩 경합**: revision 불일치 시 embed 쓰기 스킵.
- **크롤러 보존**: 재크롤이 prize/format/description/regulation_* 안 지움(undefined). hash 변경 시 pending 재큐. `crawler_upsert_preserve_test.ts` 확장.
- **검증**: 환각(원문 미존재 금액) → needs_review. 정상 → formatted/staged.
- **마스킹**: format_flags에 원문 계좌번호 미포함(회귀).
- **백필**: skipped=31/pending=50 재검증 가드.
- Deno test(edge/RPC) + Flutter 모델 테스트.

## 16. 결정 기록

| # | 결정 | 채택 |
|---|---|---|
| 1 | 요강 반영 정책(신규·기존) | **review-first**(2026-07-17 갱신): 신규·기존 모두 최초 정형화는 검수 스테이징(승인 후 반영), 재크롤만 검증 통과 시 자동 |
| 2 | 재크롤 재큐 | 크롤러 로직 + hash 비교 |
| 3 | embed 필터 | revision optimistic write + pending/processing 제외 |
| 4 | cron/배치 | */5 offset · attempts<3 · batch 바이트 상한 · lease 15분 |
| 5 | draft 포함 | 제외(status≠draft) |
| 6 | amfutsalhub reg_fields 정리 | 별도 티켓(이번 skipped) |
| 7 | format_flags 마스킹 | 원문값 금지·code/field/masked만·DB CHECK |
| 8 | 마이그레이션 주체 | apply_migration + repo 커밋 |
| — | 트리거 vs 역할분리 | 파서=메타, LLM=요강 정형화 |
| — | LLM provider | Gemini(`_shared/gemini.ts`) |

## 17. 미결 · 향후 (JY-137 연계)

- regulation_* 정규화(jsonb vs 별도 테이블), raw_html 보존정책(용량/TTL), closed 임베딩 정책, amfutsalhub 메타 정리, format_flags admin 전용 분리 → **출시 후 JY-137**에서 재점검.
- 어드민 검수 UI 상세는 구현 계획서에서.
