# 계획: 맥미니 야간 크롤 파이프라인 + 전북 파일럿

작성 2026-07-10 · Fable 에이전트 4기 병렬 조사 종합.

## 목표

1. 크롤링을 Supabase 클라우드 cron → **맥미니 야간(launchd) 잡**으로 이관 (클라우드 cron은 이미 `active=false`).
2. **전북**을 첫 확장 협회로 추가 (신규 gnuboard `board.php` 파서 + 지역 체계 편입).
3. 텍스트로 안 잡히는 정보(참가비·장소)는 **Claude가 포스터 이미지를 읽어** 보완. 결과는 항상 `draft` → 어드민 승인.

## 최종 아키텍처

```
매일 자정 (launchd, 맥미니)
  scripts/nightly-crawl.sh
   ├─ 1) deno run _local/crawl_nightly.ts   # 크롤+텍스트 파싱 (기존 파서 재사용) → Supabase draft
   ├─ 2) 포스터 이미지 URL 수집 → curl 로컬 저장
   ├─ 3) claude --bare -p (Read 전용, DB 자격증명 없음) → 포스터에서 참가비·장소 JSON 추출
   └─ 4) 스크립트가 검증 후 해당 draft 행 UPDATE (DB 쓰기는 셸만)
  → 로그 + 비용 JSONL
```

핵심 안전 원칙(에이전트1): **Claude에는 DB 쓰기를 주지 않는다.** Claude=추출 전용(Read), INSERT/UPDATE는 결정적 셸이. 포스터 속 악성 텍스트(프롬프트 인젝션)가 DB에 닿을 경로를 차단.

---

## Phase 0 — 착수 전 확인 (blocker)

- [ ] **EUC-KR 인코딩 확인** — `curl -sI https://www.jbsta.com/board.php?bo_table=schedule` 로 charset 확인. gnuboard는 EUC-KR인 경우 많음. UTF-8 아니면 파서에 `TextDecoder('euc-kr')` 분기 필수(안 하면 한글 깨져 매칭 전멸).
- [ ] **regions FK** — `tournaments.region_code`는 `regions(code)` FK. 'jeonbuk' 시드 행이 **선행**돼야 크롤 insert가 FK 위반 안 남. (Phase 1-A)
- [ ] **매칭 갭 인지** — generic 등급(beginner…)은 테니스 매칭 RPC의 `expand_gj_jn_codes()` 교차에 안 걸림 → **홈 개인화 추천엔 전북 대회 안 뜰 수 있음.** 단 대회 탭(기본 only_my_grade=false)엔 뜸. 정밀 매칭은 후속(`jb_` 코드 or RPC generic 처리).

---

## Phase 1 — 전북 지역 편입

### 1-A. DB (가장 먼저, FK 선행)
- [ ] 새 마이그레이션 `supabase/migrations/<ts>_seed_region_jeonbuk.sql` (045_seed_regions.sql 패턴):
  ```sql
  insert into public.regions (code, display_name_ko, governing_associations, uses_kato, uses_kata, notes)
  values ('jeonbuk', '전북', '{"kta"}', false, false, '전북특별자치도.')
  on conflict (code) do update set display_name_ko = excluded.display_name_ko;
  ```
  (uses_kato/kata 는 전북 KATO/KATA 활동 확인 후. 미확인 시 false.)
- [ ] `db push` 금지 → `execute_sql`로 직접 적용 + 파일은 기록.
- RPC(`tournaments_for_user`, `tournament_search_by_slots`)는 `region_code` 단순 비교라 **수정 불필요.**

### 1-B. 백엔드 (`_shared/`)
- [ ] `enums.ts` `REGION_CODES`에 `'jeonbuk'`, `REGION_LABELS`에 `jeonbuk: '전북'`. (isValid·역매핑은 자동 파생)
- [ ] `intent.ts` `REGION_ALIASES`에 `{ pattern: /(전라북도|전북특별자치도|전북)/, code: 'jeonbuk' }`.
- [ ] `tests/enums_test.ts` 지역 배열 정확일치 assert에 `'jeonbuk'` 추가 (**안 하면 CI 실패**). intent_test에도 케이스 추가.

### 1-C. Flutter
- [ ] `app/lib/utils/grade_labels.dart` `regionCodes`에 `'jeonbuk'`, `regionLabels`에 `'jeonbuk': '전북'`. (필터칩·활성필터·프로필 표시 자동 커버)
- [ ] `app/lib/screens/auth/onboarding_screen.dart` `_onboardingRegionChoices`에 `_RegionChoice(code: 'jeonbuk', label: '전북')`.

### 1-D. 배포
DB 시드 → Edge Functions 재배포(tournaments-search/submit, chat, crawl-dispatch) → Flutter. `deno test`·`flutter test` 통과 확인.

---

## Phase 2 — 전북 파서

- 파일: `_shared/crawler/parsers/gnuboard5_schedule_board.ts`, export `gnuboard5ScheduleBoardParser: ParserFn`.
- `registry.ts`에 `'gnuboard5-schedule-board'` 키 등록.
- `crawl_sources` 행: slug `tennis-jeonbuk`, url `https://www.jbsta.com/board.php?bo_table=schedule`, region `'전북'`, parser_module `'gnuboard5-schedule-board'`.

### 재사용 (기존 gj/jn 파서 골격 복사)
5단 구성(fetchListing 조건부GET → parseListing → contentHash → fetchDetail 루프 → CrawlResult), 30건 cap, 전건실패→`error`+`etag:null`, 파싱가드 실패→`saveRawDocument('failed')`, `upsertTournament`(draft), `extractVenue`(기회적).

### 신규/수정
- [ ] **목록**: `bo_table=schedule` + `wr_id=` 앵커만, **wr_id 기준 dedupe**, 빈텍스트(이미지) 앵커 skip.
- [ ] **★ canonical source_url**: 페이지네이션 파라미터(`&page=`,`&sfl=`…) 제거하고 `board.php?bo_table=schedule&wr_id=N`로 재구성 (안 하면 중복 insert).
- [ ] **표 스코프**: 문서 전체 `th`가 아니라 "경기일+신청기간 th를 모두 가진 `<table>`"을 찾아 그 표 안에서만 컬럼 인덱스/행 순회 (기존 파서의 잠재 버그 회피).
- [ ] **헤더 키워드 확장**: 경기일 `['경기일','대회일']`, 신청기간 `['신청기간','접수기간']`, 부서 `['참가부서','부서','부문']`.
- [ ] **`extractMonthDays(text)`** 신규: `(\d{1,2})월(\d{1,2})일` 전수 매치 (기존 extractDate는 4자리 연도 필수라 못 씀). 전 행 순회 → 경기일 min=start_date, max≠min이면 end_date. 신청기간 셀 마지막 날짜 max=deadline.
- [ ] **★ `inferYear(monthDays, now)`** 신규 (연도 없는 날짜):
  1. 앵커연도 = 제목/본문 4자리 연도 → 없으면 gnuboard 작성일(`#bo_v_info`) → 없으면 크롤시점 KST 연도.
  2. 시간축(신청시작→마감→경기일) 단조증가: 다음이 이전보다 앞서면 +1년(연말·연초 걸침).
  3. 크롤시점 보정(앵커가 3번 폴백일 때만): 경기일이 60일+ 과거면 +1년.
  4. sanity: 경기일이 −12~+18개월 밖이면 추론실패 → `tournament:null`.
  - `now`를 파라미터로 받아 테스트 결정성 확보.
- [ ] **등급**: `extractGJDivisions` 안 씀. 신규 `extractGenericDivisions` → codes 항상 `['beginner','intermediate','advanced']` 고정, label=참가부서 원문 join. (오매핑으로 숨는 것보다 전등급 노출이 안전, draft 검수로 보정)
- [ ] 참가비·장소·주최·요강은 텍스트에 없음 → `undefined`(organizer는 `'전북테니스협회'` 폴백).
- [ ] **테스트**: 순수함수(parseListing, 표파서, extractMonthDays, inferYear) export → 픽스처로 `deno test`. 공지 상단고정 이중출현, 연말경계 케이스 포함.

---

## Phase 3 — 로컬 야간 러너 (기존 Deno 파서 재사용)

파서·헬퍼 **한 줄도 수정 없이** 로컬 `deno run`으로 재사용. 신규는 엔트리 1개 + env + plist.

- [ ] `supabase/functions/_local/crawl_nightly.ts` (~120줄) — dispatcher 몸통 이식:
  - enabled `crawl_sources` 로드 → 소스별: `crawl_try_start` 락 → `startAudit`→`getParser`→`parser(source,{audit, previousEtag: force?null:last_etag,…})`→`finishAudit`→메트릭 UPDATE → `finally crawl_release`.
  - **자동 closed 처리 블록**(dispatcher 279–285, KST 기준) 이관 — pg_cron off 후 유일 실행처.
  - `isDue`/`MIN_INTERVAL_HOURS` 제거(야간 1회 전체 실행), **etag/content-hash no_change 감지는 유지**.
  - CLI 인자 `--slug=`,`--force`, 요약 `console.log` + `Deno.exit(errors?1:0)`.
- [ ] `_local/.env` (**gitignore**): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY=sb_secret_...` (레거시 JWT disabled → 신 키).
- [ ] `serviceClient()` 등 `_shared`는 수정 불필요. `_` 접두 디렉터리라 Supabase 배포 제외 + `../_shared` import·deno.json import map 재사용.
- 실행:
  ```sh
  cd supabase/functions
  deno run --env-file=_local/.env --allow-env --allow-read \
    --allow-net=bsjdgwmveokanclqwtvx.supabase.co,www.jbsta.com,gjtennis.kr,www.jntennis.kr,esm.sh,deno.land \
    _local/crawl_nightly.ts
  ```
- `crawl_try_start`/`crawl_release` 락 유지 → 어드민 수동 Edge 실행과 겹쳐도 안전. crawl-dispatch Edge는 **존치**(수동/긴급 경로).

---

## Phase 4 — Claude 포스터 추출

- [ ] `scripts/nightly-crawl.sh`: deno 러너 후, 이미지 없는 draft의 포스터 URL 수집 → `curl`로 로컬 저장.
- [ ] 포스터 1장 = 1회 호출 (실패 격리·비용 상한 단위):
  ```sh
  claude --bare -p "이미지 <절대경로> 를 읽고 참가비/장소/부문 추출. 불확실은 null." \
    --allowedTools "Read" --permission-mode dontAsk \
    --output-format json --json-schema '<스키마>' \
    --max-budget-usd 0.50 --max-turns 15 --model haiku
  ```
  - `--bare`(스크립트 권장, 프로젝트 hook/skill 무시) → **인증은 `ANTHROPIC_API_KEY` 필수**(키체인 안 읽음).
  - 결과 `jq '.structured_output'`; 비용 `total_cost_usd`를 JSONL 누적.
  - **DB 자격증명은 Claude 환경에 미주입.** 셸이 검증 후 draft UPDATE.
  - 프로젝트 settings allow 룰은 `-p`+미trust 시 무시되므로 **플래그로 명시**.
- [ ] haiku로 먼저 정확도 검증 → 미달 시 상위 모델.

---

## Phase 5 — 자동화 + 전환

- [ ] `~/Library/LaunchAgents/kr.allround.nightly-crawl.plist` — `StartCalendarInterval`(00:05), `WorkingDirectory`, `StandardOut/ErrPath`, `EnvironmentVariables.PATH`(claude·deno 경로 명시, launchd는 .zshrc 안 읽음).
- [ ] `scripts/nightly-crawl.sh`: `mkdir` 락(중복방지), `caffeinate -i`로 감싸 실행중 슬립 방지.
- [ ] 절전: `pmset` 상시가동 또는 자정 wake 예약. LaunchAgent는 **로그인 상태 필요** → 자동 로그인 고려.
- [ ] 테스트: `launchctl kickstart -k gui/$UID/kr.allround.nightly-crawl` 즉시 실행 확인.
- 클라우드 cron은 이미 off(`active=false`). 맥미니가 유일 크롤러. 롤백=`cron.alter_job active:=true` 한 줄.

---

## 미결정 (사용자 결정 필요)

1. **Claude 모델**: 포스터 추출을 haiku로 시작(추천, 저렴) vs sonnet.
2. **매칭 갭**: 전북 정밀 매칭(`jb_` 코드/ RPC generic 처리)을 이번에 할지 후속으로.
3. **regions 시드의 uses_kato/uses_kata**: 전북 KATO/KATA 활동 여부.
4. **실행 순서**: 데이터 먼저(Phase 1+2로 "전북 대회 뜬다" 빠르게) vs 인프라 먼저(Phase 3 로컬러너).

## 리스크

- 맥미니 절전/로그아웃 시 크롤 공백 → 알림(24h 초과) 별도 고려.
- jbsta 현재 DB 오류로 목록 1건만 노출(일시적일 수 있음).
- 연도 추론 오류 → draft 게이트가 최종 방어선.
- 가정용 IP로 크롤 → User-Agent 유지, 요청 간격 예의.
