# 협회 랭킹 미러링 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 광주·전남 협회가 공표하는 부서별 랭킹표를 크롤해 앱에서 보여준다. 앱은 점수를 계산하지 않는다.

**Architecture:** 테이블 2개로 분리한다 — `org_rankings`(미러, 크롤마다 부서 단위로 갈아엎음)와 `org_player_links`(협회 선수↔앱 계정 연결, 크롤과 독립적으로 생존). 크롤은 기존 `crawl-dispatch` + `PARSER_REGISTRY` 구조에 파서 하나를 추가하는 것으로 끝난다. 광주·전남이 동일 CMS라 파서 하나가 둘 다 처리한다.

**Tech Stack:** Postgres(Supabase) + RLS + pgTAP / Deno Edge Functions + deno-dom / Flutter + Riverpod

**설계 문서:** [`docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md`](../specs/2026-08-03-org-ranking-mirror-design.md)

## Global Constraints

- **레인**: 드론. `supabase/functions/_shared/crawler/**`, 마이그레이션, 랭킹 화면. 공유 구역(`_shared/enums.ts`, 마이그레이션 번호, `app/lib/state/**`) 수정 시 착수 즉시 공지
- **Git**: `admin 강제 머지 금지`. PR → CI 5체크 → codex 리뷰 GATE PASS → 머지. main 직접 push 불가
- **타입 안전**: TypeScript `any` 금지, Dart `dynamic` 지양. 신규 테이블은 RLS enable + 정책 필수
- **CI는 warning도 에러**: unused import/element 전부 제거
- **마이그레이션 파일명**: `YYYYMMDDHHMMSS_name.sql` (타임스탬프 형식)
- **pgTAP 파일명**: `supabase/tests/database/NNN_name.test.sql`. 현재 최신 016 → 다음 **017**부터
- **Deno 커밋 전 필수 3종**: `deno fmt --check` · `deno lint` · `deno test`. fmt 검사가 CI에 있다
- **`dart format` 실행 금지** — 로컬 포매터가 CI와 스타일이 달라 파일 전체를 재포맷한다. 주변 코드 스타일에 손으로 맞춘다
- **UI 변경 후 `flutter test` 전체 실행** — 로컬 Flutter가 CI SDK보다 구버전이라 analyze·부분 테스트로는 컴파일 차이를 못 잡는다
- **부서 카탈로그를 고치면 스냅샷 다리 3곳을 함께**: DB 마이그레이션 ↔ `app/test/fixtures/division_fallback.json` ↔ Dart 폴백
- **작업 전 `git fetch origin`** — origin/main이 세션 중 빨리 앞서간다

---

## 실측 데이터 (파서 작성 근거)

랭킹표 URL: `https://gjtennis.kr/sub4_5.php?member_kind=<부서명>` (전남은 `jntennis.kr`, 경로 동일)

부서명 7개는 **광주·전남 완전 동일**: `골드부` `국화부` `남자신인부` `남자일반부` `여자금배부` `여자신인부` `지도자부`

행 HTML 실측:

```html
<td data-table="wr_1">1</td>
<td data-table="wr_2">골드부</td>
<td data-table="wr_3"><a href="javascript:player_rank('vudghk2116')"><img src="img/binfo_x.jpg"></a></td>
<td data-table="wr_4"><a href="javascript:player_rank('vudghk2116','골드부')"><b>김평화</b></a></td>
<td data-table="wr_5">어등산/</td>
<td data-table="wr_6">2,649</td>
<td data-table="wr_6">2,649</td>
```

**함정 3개** (파서가 반드시 다뤄야 한다):

1. **`wr_6`이 두 번 나온다.** 순위포인트와 전체포인트가 같은 `data-table` 값을 쓴다 → 셀렉터로 구분 불가, **순서(index)로만** 갈린다
2. **포인트에 천 단위 콤마**가 있다 (`2,649`) → 제거 후 파싱
3. **`org_player_id`는 `player_rank('...')`의 1번 인자**다. `wr_3`(사진)에는 1개 인자, `wr_4`(성명)에는 2개 인자로 두 번 등장한다. 사진이 없는 행은 `wr_3`의 `<a>`가 비어 있을 수 있으므로 **`wr_4`에서 뽑는다**

---

## File Structure

| 파일 | 책임 |
|---|---|
| `supabase/migrations/<ts>_split_gj_jn_women_winner_divisions.sql` | 국화부·여자금배부 부서 신설 (Task 1) |
| `supabase/tests/database/017_ranking_division_catalog.test.sql` | 부서 카탈로그 pgTAP (Task 1) |
| `app/test/fixtures/division_fallback.json` | 부서 스냅샷 (Task 1에서 갱신) |
| Dart 부서 폴백 파일 | Task 1 Step 1에서 경로 확인 후 갱신 |
| `supabase/migrations/<ts>_org_ranking_mirror.sql` | 테이블 2개 + RLS + grant (Task 2) |
| `supabase/tests/database/018_org_ranking_rls.test.sql` | RLS pgTAP (Task 2) |
| `supabase/functions/_shared/crawler/parsers/gnuboard_ranking.ts` | 랭킹표 파서 (Task 3) |
| `supabase/functions/_shared/crawler/registry.ts` | 파서 등록 (Task 3, 수정) |
| `supabase/functions/tests/crawler_ranking_test.ts` | 파서 단위 테스트 (Task 3) |
| `supabase/functions/tests/fixtures/gj_ranking_gold.html` | 파서 fixture (Task 3) |
| `supabase/migrations/<ts>_ranking_crawl_sources.sql` | 크롤 소스 2건 + Storage 버킷 (Task 3) |
| `supabase/migrations/<ts>_org_ranking_claim_rpc.sql` | 후보 조회 RPC (Task 4) |
| `supabase/tests/database/019_org_ranking_claim.test.sql` | 클레임 pgTAP (Task 4) |
| `app/lib/models/org_ranking.dart` | 랭킹 행·클레임 모델 (Task 5) |
| `app/lib/screens/admin/ranking_claims_tab.dart` | 관리자 승인 큐 (Task 5) |
| `app/test/ranking_claims_test.dart` | 승인 큐 위젯 테스트 (Task 5) |
| `app/lib/screens/rankings/rankings_screen.dart` | 랭킹 화면 (Task 6) |
| `app/test/rankings_screen_test.dart` | 랭킹 화면 위젯 테스트 (Task 6) |
| 개인정보처리방침 | Task 7 Step 1에서 경로 확인 후 수정 |

**Flutter 관례** (Task 5·6에서 그대로 따른다):
- 테스트는 `app/test/` **평면 구조**다. 하위 폴더를 만들지 않는다(`fixtures/`만 예외)
- import 는 `package:allround/...`
- 위젯 테스트는 `ProviderScope` + `MaterialApp(theme: AppTheme.light())` 로 감싼다. **감싸지 않으면 Row 안 비확장 버튼이 무한 폭으로 크래시한다**
- 관리자 탭은 데이터를 주입받는 `StatelessWidget` 카드로 쪼갠다 (`crawl_sources_tab.dart:6` `SourceCard` 패턴) — 그래야 네트워크 없이 테스트된다

---

## Task 1: 부서 카탈로그 — 국화부·여자금배부 신설

협회 랭킹표는 국화부와 여자금배부가 **별도 랭킹**인데, 카탈로그는 `gj_w_winner`(여자우승자부) 하나에 두 이름을 alias로 합쳐놨다. `division_code` FK를 걸려면 분리해야 한다.

기존 행:
```
('gj_w_winner', 'gj', '여자우승자부', '{우승자부,여자우승자,국화,금배}', 'advanced', 'female', null, true, 'doubles', 'sido_std:w_winner')
```

**방침**: `*_w_winner`는 **삭제하지 않는다**(대회 요강에 "여자우승자부"가 등장하고, 이미 등급으로 등록한 유저가 있을 수 있다). alias에서 `국화`·`금배`만 떼고 새 코드 2개를 추가한다.

**Files:**
- Create: `supabase/migrations/<타임스탬프>_split_gj_jn_women_winner_divisions.sql`
- Modify: `app/test/fixtures/division_fallback.json`
- Modify: Dart 폴백 파일 (Step 1에서 경로 확인)

**Interfaces:**
- Produces: 부서 코드 `gj_w_gukhwa`, `gj_w_geumbae`, `jn_w_gukhwa`, `jn_w_geumbae` — Task 3 파서가 `member_kind` → 코드 매핑에 사용

- [ ] **Step 1: 현재 상태와 Dart 폴백 경로 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-division-split origin/main
grep -rn "gj_w_winner" supabase/migrations/20260710020000_tennis_orgs_divisions_catalog.sql
grep -rln "gj_w_winner\|여자우승자부" app/lib/
```

`app/lib/` 결과에서 폴백 목록을 들고 있는 파일 경로를 기록한다. 이후 스텝의 "Dart 폴백"은 이 파일을 가리킨다.

- [ ] **Step 2: 기존 유저 영향 확인 (읽기 전용)**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c \
  "select count(*) from public.users where division_codes && array['gj_w_winner','jn_w_winner'];"
```

0이 아니면 그 유저들은 그대로 둔다(마이그레이션에서 강제 이전하지 않는다). 결과를 마이그레이션 주석에 기록한다.

- [ ] **Step 3: 실패하는 pgTAP 테스트를 먼저 쓴다**

`supabase/tests/database/017_ranking_division_catalog.test.sql`:

```sql
begin;
select plan(6);

-- 협회 랭킹표의 7개 부서가 모두 카탈로그에 있어야 한다 (광주)
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_m_gold','gj_m_general','gj_m_rookie','gj_m_instructor',
                  'gj_w_rookie','gj_w_gukhwa','gj_w_geumbae')),
  7, '광주 랭킹 부서 7개가 카탈로그에 존재');

select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('jn_m_gold','jn_m_general','jn_m_rookie','jn_m_instructor',
                  'jn_w_rookie','jn_w_gukhwa','jn_w_geumbae')),
  7, '전남 랭킹 부서 7개가 카탈로그에 존재');

-- 새 부서는 랭킹 등급이어야 한다
select is(
  (select bool_and(is_ranking_grade) from public.tennis_divisions
   where code in ('gj_w_gukhwa','gj_w_geumbae','jn_w_gukhwa','jn_w_geumbae')),
  true, '국화·금배는 is_ranking_grade = true');

-- 기존 여자우승자부는 살아 있어야 한다
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_w_winner','jn_w_winner')),
  2, '여자우승자부는 삭제되지 않았다');

-- alias 충돌 제거: '국화'/'금배' 가 winner 의 synonyms 에 남아 있으면 안 된다
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_w_winner','jn_w_winner')
     and synonyms && array['국화','금배']),
  0, 'winner 의 synonyms 에서 국화·금배 제거됨');

-- 새 부서에 synonyms 가 붙어 있어야 요강 파서가 매칭한다
select is(
  (select bool_and(array_length(synonyms, 1) > 0) from public.tennis_divisions
   where code in ('gj_w_gukhwa','gj_w_geumbae','jn_w_gukhwa','jn_w_geumbae')),
  true, '새 부서에 synonyms 존재');

select * from finish();
rollback;
```

- [ ] **Step 4: 테스트가 실패하는 것을 확인한다**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/017_ranking_division_catalog.test.sql
```

Expected: FAIL — `gj_w_gukhwa` 등이 없어 첫 번째 단언부터 `7`이 아니라 `5`가 나온다.

- [ ] **Step 5: 마이그레이션 작성**

`supabase/migrations/<타임스탬프>_split_gj_jn_women_winner_divisions.sql`:

```sql
-- 국화부 · 여자금배부 분리
--
-- 배경: 협회 랭킹표(sub4_5.php)는 국화부와 여자금배부를 별도 랭킹으로 공표하는데,
--   카탈로그는 *_w_winner(여자우승자부) 하나에 두 이름을 synonyms 로 합쳐놨다.
--   org_rankings.division_code FK 를 걸려면 별도 행이 필요하다.
--
-- 방침: *_w_winner 는 삭제하지 않는다. 대회 요강에 "여자우승자부"가 실제로 등장하고,
--   이미 등급으로 등록한 유저가 있을 수 있다(Step 2 확인 결과: <숫자>명).
--   synonyms 에서 국화·금배만 떼어 새 코드로 옮긴다.
--
-- 근거: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md §8

begin;

-- 1) 기존 winner 에서 국화·금배 alias 제거
update public.tennis_divisions
set synonyms = array_remove(array_remove(synonyms, '국화'), '금배')
where code in ('gj_w_winner', 'jn_w_winner');

-- 2) 국화부 · 여자금배부 신설 (광주·전남 동일 구조)
insert into public.tennis_divisions
  (code, org, label, synonyms, level, gender, score_max, is_ranking_grade, format, std_key)
values
  ('gj_w_gukhwa',  'gj', '국화부',     array['국화부','국화'],       'advanced', 'female', null, true, 'doubles', 'sido_std:w_gukhwa'),
  ('gj_w_geumbae', 'gj', '여자금배부', array['여자금배부','금배부','금배'], 'advanced', 'female', null, true, 'doubles', 'sido_std:w_geumbae'),
  ('jn_w_gukhwa',  'jn', '국화부',     array['국화부','국화'],       'advanced', 'female', null, true, 'doubles', 'sido_std:w_gukhwa'),
  ('jn_w_geumbae', 'jn', '여자금배부', array['여자금배부','금배부','금배'], 'advanced', 'female', null, true, 'doubles', 'sido_std:w_geumbae')
on conflict (code) do nothing;

commit;
```

**주의**: 컬럼 목록과 순서는 `supabase/migrations/20260710020000_tennis_orgs_divisions_catalog.sql:77-88`의 실제 INSERT를 그대로 따라야 한다. Step 1에서 확인한 실제 컬럼과 다르면 실제 것을 쓴다. `is_active` 컬럼이 별도로 있으면 `true`를 명시한다.

- [ ] **Step 6: 테스트가 통과하는 것을 확인한다**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/017_ranking_division_catalog.test.sql
```

Expected: PASS 6/6

- [ ] **Step 7: 스냅샷 다리 갱신 — fixture**

`app/test/fixtures/division_fallback.json`에 4개 항목을 추가한다. 기존 항목과 **정렬 순서·들여쓰기·키 순서를 동일하게** 맞춘다:

```json
{"org": "gj", "code": "gj_w_geumbae", "label": "여자금배부", "isActive": true, "isRankingGrade": true},
{"org": "gj", "code": "gj_w_gukhwa", "label": "국화부", "isActive": true, "isRankingGrade": true},
{"org": "jn", "code": "jn_w_geumbae", "label": "여자금배부", "isActive": true, "isRankingGrade": true},
{"org": "jn", "code": "jn_w_gukhwa", "label": "국화부", "isActive": true, "isRankingGrade": true}
```

- [ ] **Step 8: 스냅샷 다리 갱신 — Dart 폴백**

Step 1에서 찾은 Dart 폴백 파일에 같은 4개를 추가한다. **`dart format`을 실행하지 말고** 주변 항목의 들여쓰기·따옴표 스타일에 손으로 맞춘다.

- [ ] **Step 9: 정합성 검사 통과 확인**

```bash
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  python3 scripts/harness/check_division_parity.py
cd app && flutter analyze && flutter test
```

Expected: parity 검사 PASS, flutter analyze 무경고, flutter test 전체 PASS

- [ ] **Step 10: 커밋 & PR**

```bash
git add supabase/migrations supabase/tests/database/017_ranking_division_catalog.test.sql \
        app/test/fixtures/division_fallback.json app/lib
git commit -m "feat(db): 국화부·여자금배부 부서 신설 — 협회 랭킹 미러링 선행

협회 랭킹표는 국화부와 여자금배부를 별도 랭킹으로 공표하는데 카탈로그는
*_w_winner 하나에 alias 로 합쳐놨다. org_rankings.division_code FK 를 걸려면
별도 행이 필요하다. winner 는 유지(요강에 실제 등장 + 기존 유저 등급).

스냅샷 다리 3곳 동기화: DB ↔ fixture ↔ Dart 폴백."
git push -u origin feature/JY-ranking-division-split
gh pr create --fill
```

CI 5체크 통과 후 codex 리뷰 GATE PASS를 받고 머지한다.

---

## Task 2: 테이블 2개 + RLS

**Files:**
- Create: `supabase/migrations/<타임스탬프>_org_ranking_mirror.sql`
- Create: `supabase/tests/database/018_org_ranking_rls.test.sql`

**Interfaces:**
- Consumes: Task 1의 부서 코드
- Produces: 테이블 `public.org_rankings` (컬럼 `org_code, division_code, rank, player_name, org_player_id, club_raw, rank_points, total_points, source_url, fetched_at`), `public.org_player_links` (컬럼 `org_code, org_player_id, user_id, status, claimed_at, decided_at, decided_by`) — Task 3 파서가 `org_rankings`에 쓰고, Task 4 RPC가 둘 다 읽는다

- [ ] **Step 1: 브랜치 생성 + 기존 grant 관례 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-tables origin/main
grep -rn "grant all" supabase/migrations/20260724060000*.sql | head -20
cat supabase/tests/database/011_api_role_grants.test.sql | head -40
```

새 테이블에 필요한 grant 형식을 기록한다. **클린 재생 시 grant가 통째로 누락되는 이력이 있으므로 마이그레이션에 명시적으로 넣는다.**

- [ ] **Step 2: 실패하는 pgTAP 테스트를 먼저 쓴다**

`supabase/tests/database/018_org_ranking_rls.test.sql`:

```sql
begin;
select plan(9);

-- 테이블 존재
select has_table('public', 'org_rankings', 'org_rankings 테이블 존재');
select has_table('public', 'org_player_links', 'org_player_links 테이블 존재');

-- RLS 활성화
select is(
  (select relrowsecurity from pg_class where oid = 'public.org_rankings'::regclass),
  true, 'org_rankings RLS enabled');
select is(
  (select relrowsecurity from pg_class where oid = 'public.org_player_links'::regclass),
  true, 'org_player_links RLS enabled');

-- 시드 데이터
insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 1, '김평화', 'vudghk2116', '어등산/', 2649, 2649,
   'https://gjtennis.kr/sub4_5.php?member_kind=골드부');

-- anon 은 정책이 없어 0행이어야 한다 (grant 가 있어도)
set local role anon;
select is(
  (select count(*)::int from public.org_rankings),
  0, 'anon 은 org_rankings 를 볼 수 없다');
reset role;

-- 유저가 남의 클레임을 confirmed 로 만들 수 없다
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local')
on conflict do nothing;
insert into public.users (id, name) values
  ('11111111-1111-1111-1111-111111111111', '김평화'),
  ('22222222-2222-2222-2222-222222222222', '남의계정')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- 본인 pending 클레임은 만들 수 있다
select lives_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'vudghk2116', '11111111-1111-1111-1111-111111111111', 'pending')$$,
  '본인 pending 클레임 생성 가능');

-- 스스로 confirmed 로 넣는 것은 막혀야 한다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'zzz', '11111111-1111-1111-1111-111111111111', 'confirmed')$$,
  '42501', null, '유저가 스스로 confirmed 로 넣을 수 없다');

-- 남의 이름으로 클레임하는 것도 막혀야 한다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'yyy', '22222222-2222-2222-2222-222222222222', 'pending')$$,
  '42501', null, '남의 user_id 로 클레임할 수 없다');

reset role;
reset request.jwt.claims;

-- confirmed 는 협회 선수당 1명만
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'dupe', '11111111-1111-1111-1111-111111111111', 'confirmed');
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'dupe', '22222222-2222-2222-2222-222222222222', 'confirmed')$$,
  '23505', null, '같은 협회 선수에 confirmed 가 둘일 수 없다');

select * from finish();
rollback;
```

- [ ] **Step 3: 테스트가 실패하는 것을 확인한다**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/018_org_ranking_rls.test.sql
```

Expected: FAIL — `org_rankings` 테이블이 없어 `has_table`부터 실패

- [ ] **Step 4: 마이그레이션 작성**

`supabase/migrations/<타임스탬프>_org_ranking_mirror.sql`:

```sql
-- 협회 랭킹 미러 + 선수↔계정 연결
--
-- 설계: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md
--
-- 왜 테이블이 둘인가: org_rankings 는 크롤마다 부서 단위로 갈아엎는다(협회가 시즌·공표일을
--   안 주므로 "현재 상태"만 유지). 힘들게 확인한 계정 연결이 그때마다 날아가면 안 되므로
--   org_player_links 를 분리한다.
--
-- 앱은 점수를 계산하지 않는다. 협회 공표값을 그대로 옮긴다.

begin;

-- ═══════════════════════════════════════════════
-- org_rankings — 협회 공표 순위표 미러 (현재상태)
-- ═══════════════════════════════════════════════
create table public.org_rankings (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  division_code text not null references public.tennis_divisions(code),
  rank          int  not null check (rank > 0),
  player_name   text not null,
  -- 협회 시스템 선수 아이디. 랭킹표 HTML 의 player_rank('...') 1번 인자.
  -- null 허용: 링크가 없는 행(사진·이름 셀에 <a> 가 없는 경우) 대비.
  org_player_id text,
  club_raw      text,  -- 소속 원문 그대로('화순/토요피닉스/'). 파싱·정규화 안 함
  rank_points   int  not null check (rank_points  >= 0),  -- 화면의 '순위포인트'
  total_points  int  not null check (total_points >= 0),  -- 화면의 '전체포인트'
  source_url    text not null,
  fetched_at    timestamptz not null default now(),
  unique (org_code, division_code, rank),
  unique (org_code, division_code, org_player_id)
);

comment on table public.org_rankings is
  '협회 공표 랭킹표 미러. 크롤마다 부서 단위 delete+insert. 앱이 계산한 값이 아니다.';
comment on column public.org_rankings.rank_points is
  '협회 화면의 순위포인트. 규정상 total_points 와 다른 집계(베스트25 vs 베스트15)여야 하나 현재 협회 화면은 같은 값이다 — 합치지 말 것.';

create index org_rankings_player_name_idx on public.org_rankings (player_name);
create index org_rankings_org_player_idx  on public.org_rankings (org_code, org_player_id);

alter table public.org_rankings enable row level security;

-- 읽기: 로그인 유저만. anon 없음 — 비로그인 인터넷에 실명 명단을 재공개하지 않는다.
create policy org_rankings_read on public.org_rankings
  for select using (auth.role() = 'authenticated');

-- 쓰기: 크롤러는 service_role(RLS 우회), 수동 교정은 admin
create policy org_rankings_admin on public.org_rankings
  for all using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════
-- org_player_links — 협회 선수 ↔ 앱 계정
-- ═══════════════════════════════════════════════
create table public.org_player_links (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  org_player_id text not null,
  -- 탈퇴 시 연결 즉시 소멸. 단 org_rankings 의 실명 행은 남는다(협회가 여전히 공표 중).
  user_id       uuid not null references public.users(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending','confirmed','rejected')),
  claimed_at    timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid references public.users(id),
  unique (org_code, org_player_id, user_id)
);

comment on table public.org_player_links is
  '협회 선수 ↔ 앱 계정 연결. 크롤과 독립적으로 생존한다(미러는 갈아엎어도 링크는 산다).';

-- confirmed 는 1:1 강제. pending 은 여럿 허용 — 경합 클레임을 관리자가 보고 고른다.
create unique index org_player_links_confirmed_player_key
  on public.org_player_links (org_code, org_player_id) where status = 'confirmed';
create unique index org_player_links_confirmed_user_key
  on public.org_player_links (org_code, user_id) where status = 'confirmed';

alter table public.org_player_links enable row level security;

create policy org_player_links_claim on public.org_player_links
  for insert with check (user_id = (select auth.uid()) and status = 'pending');

create policy org_player_links_read on public.org_player_links
  for select using (user_id = (select auth.uid()) or status = 'confirmed');

create policy org_player_links_withdraw on public.org_player_links
  for delete using (user_id = (select auth.uid()) and status = 'pending');

create policy org_player_links_admin on public.org_player_links
  for all using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════
-- grant — 클린 재생 시 누락 이력이 있어 명시한다. 실제 게이트는 RLS.
-- ═══════════════════════════════════════════════
grant select on public.org_rankings to anon, authenticated;
grant all    on public.org_rankings to service_role;
grant select, insert, delete on public.org_player_links to anon, authenticated;
grant all    on public.org_player_links to service_role;

commit;
```

**주의**: `grant` 대상과 형식은 Step 1에서 확인한 `20260724060000` 관례를 따른다. 다르면 실제 관례를 쓴다.

- [ ] **Step 5: 테스트가 통과하는 것을 확인한다**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/018_org_ranking_rls.test.sql
```

Expected: PASS 9/9

- [ ] **Step 6: 변이 주입으로 역검증**

초록불이 증거인지 확인한다. 마이그레이션에서 `org_rankings_read` 정책의 `auth.role() = 'authenticated'`를 잠시 `true`로 바꾸고 `supabase db reset` 후 테스트를 다시 돌린다.

Expected: "anon 은 org_rankings 를 볼 수 없다" 단언이 **실패**해야 한다. 실패하지 않으면 그 테스트는 아무것도 검사하지 않는 것이다. 확인 후 원복한다.

- [ ] **Step 7: advisor 확인**

Supabase MCP `get_advisors`로 security·performance lint를 확인한다. 새 테이블 관련 경고(RLS initplan, 정책 중복 등)가 나오면 이 PR에서 고친다.

- [ ] **Step 8: 커밋 & PR**

```bash
git add supabase/migrations supabase/tests/database/018_org_ranking_rls.test.sql
git commit -m "feat(db): 협회 랭킹 미러 테이블 2개 + RLS

org_rankings(미러, 크롤마다 갈아엎음) / org_player_links(계정 연결, 독립 생존).
anon 읽기 정책 없음 — 비로그인 인터넷에 실명 명단을 재공개하지 않는다.
confirmed 는 부분 유니크 인덱스로 협회 선수당 1명 강제."
git push -u origin feature/JY-ranking-tables
gh pr create --fill
```

---

## Task 3: 랭킹 파서 + 크롤 소스 등록

**Files:**
- Create: `supabase/functions/_shared/crawler/parsers/gnuboard_ranking.ts`
- Create: `supabase/functions/tests/crawler_ranking_test.ts`
- Create: `supabase/functions/tests/fixtures/gj_ranking_gold.html` (실제 응답 일부를 저장)
- Modify: `supabase/functions/_shared/crawler/registry.ts`
- Create: `supabase/migrations/<타임스탬프>_ranking_crawl_sources.sql`

**Interfaces:**
- Consumes: Task 2의 `org_rankings`, Task 1의 부서 코드
- Produces: `parseRankingRows(html: string): RankingRow[]` — 순수 함수, 테스트가 이것만 검증한다. `RankingRow = { rank: number; playerName: string; orgPlayerId: string | null; clubRaw: string | null; rankPoints: number; totalPoints: number }`. 파서 키 `'gnuboard-ranking'`

- [ ] **Step 1: 브랜치 + fixture 확보**

```bash
git fetch origin && git checkout -b feature/JY-ranking-crawler origin/main
mkdir -p supabase/functions/tests/fixtures
curl -s "https://gjtennis.kr/sub4_5.php?member_kind=%EA%B3%A8%EB%93%9C%EB%B6%80" \
  -o /tmp/gj_gold_full.html
```

전체 파일은 360KB로 크다. **상위 5행 + 0점 행 2행 + 사진 없는 행 1행**만 잘라 `supabase/functions/tests/fixtures/gj_ranking_gold.html`로 저장한다. `<table class="list_tb">` 여는 태그부터 닫는 태그까지 유효한 HTML이어야 한다.

- [ ] **Step 2: 실패하는 파서 테스트를 먼저 쓴다**

`supabase/functions/tests/crawler_ranking_test.ts`:

```ts
import { assertEquals } from 'jsr:@std/assert';
import { parseRankingRows } from '../_shared/crawler/parsers/gnuboard_ranking.ts';

const html = await Deno.readTextFile(
  new URL('./fixtures/gj_ranking_gold.html', import.meta.url),
);

Deno.test('랭킹표 행을 파싱한다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows[0].rank, 1);
  assertEquals(rows[0].playerName, '김평화');
  assertEquals(rows[0].orgPlayerId, 'vudghk2116');
  assertEquals(rows[0].clubRaw, '어등산/');
});

Deno.test('천 단위 콤마를 제거하고 숫자로 만든다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows[0].rankPoints, 2649);
  assertEquals(rows[0].totalPoints, 2649);
});

Deno.test('순위포인트와 전체포인트를 순서로 구분한다 (같은 data-table 값)', () => {
  const twoCells = `
    <table class="list_tb">
    <tr>
      <td data-table="wr_1">7</td>
      <td data-table="wr_2">골드부</td>
      <td data-table="wr_3"></td>
      <td data-table="wr_4"><a href="javascript:player_rank('abc','골드부')"><b>홍길동</b></a></td>
      <td data-table="wr_5">클럽/</td>
      <td data-table="wr_6">1,000</td>
      <td data-table="wr_6">2,000</td>
    </tr>
    </table>`;
  const rows = parseRankingRows(twoCells);
  assertEquals(rows[0].rankPoints, 1000);
  assertEquals(rows[0].totalPoints, 2000);
});

Deno.test('0점 선수도 파싱은 한다 (필터는 상위 계층 책임)', () => {
  const rows = parseRankingRows(html);
  const zeros = rows.filter((r) => r.totalPoints === 0);
  assertEquals(zeros.length > 0, true);
});

Deno.test('사진 링크가 없어도 성명 셀에서 아이디를 뽑는다', () => {
  const noPhoto = `
    <table class="list_tb">
    <tr>
      <td data-table="wr_1">9</td>
      <td data-table="wr_2">골드부</td>
      <td data-table="wr_3"></td>
      <td data-table="wr_4"><a href="javascript:player_rank('nophoto','골드부')"><b>사진없음</b></a></td>
      <td data-table="wr_5"></td>
      <td data-table="wr_6">10</td>
      <td data-table="wr_6">10</td>
    </tr>
    </table>`;
  const rows = parseRankingRows(noPhoto);
  assertEquals(rows[0].orgPlayerId, 'nophoto');
  assertEquals(rows[0].clubRaw, null);
});

Deno.test('헤더 행은 건너뛴다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows.every((r) => Number.isInteger(r.rank) && r.rank > 0), true);
});
```

- [ ] **Step 3: 테스트가 실패하는 것을 확인한다**

```bash
cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_ranking_test.ts
```

Expected: FAIL — `gnuboard_ranking.ts` 모듈이 없다

- [ ] **Step 4: 파서 작성**

`supabase/functions/_shared/crawler/parsers/gnuboard_ranking.ts`:

```ts
// _shared/crawler/parsers/gnuboard_ranking.ts
//
// 광주·전남 협회 부서별 랭킹표 parser.
//   URL: {base}/sub4_5.php?member_kind={부서명}
//   광주(gjtennis.kr)·전남(jntennis.kr)이 동일 CMS 라 parser 하나로 둘 다 처리한다.
//
// 실측 구조(2026-08-03 확인):
//   <td data-table="wr_1">순위</td>
//   <td data-table="wr_2">부서</td>
//   <td data-table="wr_3"><a href="javascript:player_rank('아이디')"><img></a></td>
//   <td data-table="wr_4"><a href="javascript:player_rank('아이디','부서')"><b>성명</b></a></td>
//   <td data-table="wr_5">소속</td>
//   <td data-table="wr_6">순위포인트</td>
//   <td data-table="wr_6">전체포인트</td>   ← 같은 data-table 값. 순서로만 구분된다
//
// 규약:
//   - 0점 선수는 저장하지 않는다(개인정보 최소화). 순위는 협회 값을 그대로 쓰므로
//     0점 구간을 버려도 남는 행의 rank 가 깨지지 않는다.
//   - 개인 상세(sub4_6_rank.php)는 fetch 하지 않는다. 선수당 1요청 × 수천 명 방지 겸.
//   - 협회가 시즌·공표일을 주지 않으므로 부서 단위 delete+insert 로 현재상태만 유지한다.
//   - 앱은 점수를 계산하지 않는다. 협회 공표값을 그대로 옮긴다.
//
// 설계: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md

import { DOMParser } from 'deno-dom';
import { serviceClient } from '../../supabase.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};

/** 협회 랭킹표 member_kind → 부서 코드 접미사. 광주·전남 동일 7개. */
const MEMBER_KIND_SUFFIX: Record<string, string> = {
  '골드부': '_m_gold',
  '남자일반부': '_m_general',
  '남자신인부': '_m_rookie',
  '지도자부': '_m_instructor',
  '여자신인부': '_w_rookie',
  '국화부': '_w_gukhwa',
  '여자금배부': '_w_geumbae',
};

export interface RankingRow {
  rank: number;
  playerName: string;
  orgPlayerId: string | null;
  clubRaw: string | null;
  rankPoints: number;
  totalPoints: number;
}

type El = {
  getAttribute(name: string): string | null;
  textContent: string;
  querySelector(sel: string): El | null;
  querySelectorAll(sel: string): ArrayLike<El> & Iterable<El>;
};

/** '2,649' → 2649. 숫자가 아니면 0. */
function toPoints(raw: string): number {
  const n = Number.parseInt(raw.replace(/[^0-9]/g, ''), 10);
  return Number.isNaN(n) ? 0 : n;
}

/** javascript:player_rank('vudghk2116','골드부') → 'vudghk2116' */
function extractPlayerId(cell: El | null): string | null {
  if (!cell) return null;
  const anchor = cell.querySelector('a');
  const href = anchor?.getAttribute('href') ?? '';
  const m = href.match(/player_rank\(\s*'([^']+)'/);
  return m ? m[1] : null;
}

function textOf(cell: El | null): string {
  return (cell?.textContent ?? '').trim();
}

/**
 * 랭킹표 HTML → 행 배열. 순수 함수(네트워크·DB 접근 없음)라 테스트가 이것만 검증한다.
 * 0점 필터는 여기서 하지 않는다 — 호출자 책임.
 */
export function parseRankingRows(html: string): RankingRow[] {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  if (!doc) return [];

  const out: RankingRow[] = [];
  for (const tr of doc.querySelectorAll('tr') as unknown as Iterable<El>) {
    const cells = Array.from(tr.querySelectorAll('td') as unknown as Iterable<El>);
    if (cells.length < 7) continue; // 헤더 행(th) · 안내 행

    const rank = Number.parseInt(textOf(cells[0]).replace(/[^0-9]/g, ''), 10);
    if (!Number.isInteger(rank) || rank <= 0) continue;

    const nameCell = cells[3];
    const playerName = textOf(nameCell);
    if (!playerName) continue;

    const club = textOf(cells[4]);

    out.push({
      rank,
      playerName,
      // 성명 셀에서 뽑는다 — 사진이 없는 행은 wr_3 의 <a> 가 비어 있다
      orgPlayerId: extractPlayerId(nameCell) ?? extractPlayerId(cells[2]),
      clubRaw: club === '' ? null : club,
      // wr_6 이 두 번 나오므로 순서로 가른다
      rankPoints: toPoints(textOf(cells[5])),
      totalPoints: toPoints(textOf(cells[6])),
    });
  }
  return out;
}

/**
 * 한 협회의 랭킹 부서 7개를 순회해 org_rankings 를 부서 단위로 갈아엎는다.
 * source.url 은 base URL(예: 'https://gjtennis.kr'), source.org_code 는 'gj' | 'jn'.
 */
export const gnuboardRankingParser: ParserFn = async (
  source: CrawlSource,
  _ctx: ParserContext,
): Promise<CrawlResult> => {
  const org = source.org_code;
  if (!org) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: 'org_code 가 없다 — crawl_sources 설정 확인',
    };
  }

  const db = serviceClient();
  const base = source.url.replace(/\/+$/, '');
  let fetched = 0;
  let inserted = 0;
  const failures: string[] = [];

  for (const [memberKind, suffix] of Object.entries(MEMBER_KIND_SUFFIX)) {
    const divisionCode = `${org}${suffix}`;
    const url = `${base}/sub4_5.php?member_kind=${encodeURIComponent(memberKind)}`;

    let html: string;
    try {
      const res = await fetch(url, { headers: COMMON_HEADERS });
      if (!res.ok) {
        failures.push(`${memberKind}: HTTP ${res.status}`);
        continue;
      }
      html = await res.text();
    } catch (e) {
      failures.push(`${memberKind}: ${e instanceof Error ? e.message : String(e)}`);
      continue;
    }

    const rows = parseRankingRows(html);
    fetched += rows.length;

    // 0점 선수 미저장 — 개인정보 최소화. 순위는 협회 값 그대로라 안 깨진다.
    const scored = rows.filter((r) => r.totalPoints > 0 || r.rankPoints > 0);

    // 원본 보관: 연말 리셋이 미러를 덮어쓰기 전의 유일한 보험이다.
    await archiveSnapshot(db, org, divisionCode, html);

    const { error: delErr } = await db
      .from('org_rankings')
      .delete()
      .eq('org_code', org)
      .eq('division_code', divisionCode);
    if (delErr) {
      failures.push(`${memberKind}: delete ${delErr.message}`);
      continue;
    }

    if (scored.length === 0) continue;

    const { error: insErr } = await db.from('org_rankings').insert(
      scored.map((r) => ({
        org_code: org,
        division_code: divisionCode,
        rank: r.rank,
        player_name: r.playerName,
        org_player_id: r.orgPlayerId,
        club_raw: r.clubRaw,
        rank_points: r.rankPoints,
        total_points: r.totalPoints,
        source_url: url,
      })),
    );
    if (insErr) {
      failures.push(`${memberKind}: insert ${insErr.message}`);
      continue;
    }
    inserted += scored.length;
  }

  return {
    fetched_count: fetched,
    inserted_count: inserted,
    updated_count: 0,
    status: failures.length === Object.keys(MEMBER_KIND_SUFFIX).length ? 'error' : 'ok',
    error: failures.length > 0 ? failures.join(' | ') : undefined,
  };
};

/** 크롤한 원본 HTML 을 비공개 버킷에 보관한다. 실패해도 크롤 자체는 계속한다. */
async function archiveSnapshot(
  db: ReturnType<typeof serviceClient>,
  org: string,
  divisionCode: string,
  html: string,
): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const path = `${org}/${divisionCode}/${day}.html`;
  const { error } = await db.storage
    .from('ranking-snapshots')
    .upload(path, new Blob([html], { type: 'text/html' }), { upsert: true });
  if (error) console.error(`[ranking] 원본 보관 실패 ${path}: ${error.message}`);
}
```

**주의**: `serviceClient()`의 실제 import 경로와 시그니처는 기존 파서(`kato_openlist.ts`)와 `_shared/supabase.ts`를 확인해 맞춘다. Storage API 호출 형식도 기존 사용처(`account_deletion_storage_test.ts`가 참조하는 코드)를 따른다.

- [ ] **Step 5: 테스트가 통과하는 것을 확인한다**

```bash
cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_ranking_test.ts
```

Expected: PASS 6/6

- [ ] **Step 6: registry 등록**

`supabase/functions/_shared/crawler/registry.ts`를 수정한다:

```ts
import { gnuboardRankingParser } from './parsers/gnuboard_ranking.ts';
```

를 기존 import 옆에 추가하고, `PARSER_REGISTRY`에 항목을 추가한다:

```ts
  'gnuboard-ranking': gnuboardRankingParser,
```

- [ ] **Step 7: Storage 버킷 + 크롤 소스 마이그레이션**

`supabase/migrations/<타임스탬프>_ranking_crawl_sources.sql`:

```sql
-- 협회 랭킹 크롤 소스 + 원본 보관 버킷
--
-- 소스는 협회당 1건. 파서가 랭킹 부서 7개를 순회한다(부서별 URL 을 소스로 쪼개면
-- 14건이 되고 부서 추가마다 소스 관리가 따라온다).
--
-- 원본 보관이 필수인 이유: 호남 3개 협회 모두 연초에 포인트를 리셋한다.
-- 2027년 1월 첫 크롤이 2026 최종 순위를 영영 덮으므로, 12월 마지막 크롤 원본이
-- 유일한 보험이다. 설계 §7 ①.

begin;

insert into storage.buckets (id, name, public)
values ('ranking-snapshots', 'ranking-snapshots', false)
on conflict (id) do nothing;

insert into public.crawl_sources
  (slug, name, url, sport, region, org_code, source_type,
   parser_module, schedule_cron, enabled, notes)
values
  ('tennis-gwangju-ranking', '광주테니스협회 부서별랭킹',
   'https://gjtennis.kr', 'tennis', '광주', 'gj', 'board',
   'gnuboard-ranking', '10 22 * * *', true,
   '부서 7개 순회. 0점 선수 미저장. 협회 동의 하에 크롤.'),
  ('tennis-jeonnam-ranking', '전남테니스협회 부서별랭킹',
   'https://jntennis.kr', 'tennis', '전남', 'jn', 'board',
   'gnuboard-ranking', '20 22 * * *', true,
   '광주와 동일 CMS. 2026년부터 광주와 랭킹 분리 운영.')
on conflict (slug) do nothing;

commit;
```

**주의**: `crawl_sources`의 실제 컬럼 목록은 `019_crawl_sources.sql`과 `20260730010000_gwangju_gu_divisions_and_sources.sql:92-104`를 확인해 맞춘다(`region_code` 컬럼이 있으면 함께 넣는다).

- [ ] **Step 8: 로컬 통합 확인**

```bash
supabase db reset
cd supabase/functions
deno fmt --check */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno lint --config deno.json _shared/crawler/parsers/gnuboard_ranking.ts
deno check --config deno.json _shared/crawler/parsers/gnuboard_ranking.ts
deno test --config deno.json --allow-env --allow-read tests
```

Expected: fmt·lint·check 무경고, 전체 테스트 PASS

- [ ] **Step 9: 커밋 & PR**

```bash
git add supabase/functions supabase/migrations
git commit -m "feat(crawler): 협회 부서별 랭킹표 파서

광주·전남 동일 CMS 라 파서 하나로 둘 다 처리. 소스는 협회당 1건이고
파서가 랭킹 부서 7개를 순회한다.

파싱 함정 3개: 순위/전체 포인트가 같은 data-table=wr_6 라 순서로만 갈린다,
포인트에 천 단위 콤마, 사진 없는 행은 성명 셀에서 아이디를 뽑아야 한다.

0점 선수 미저장(개인정보 최소화). 크롤 원본은 비공개 버킷에 보관 —
연초 포인트 리셋이 미러를 덮기 전의 유일한 보험."
git push -u origin feature/JY-ranking-crawler
gh pr create --fill
```

**머지 후 Edge Function 수동 배포가 필요하다** (CI 자동배포 없음):

```bash
supabase functions deploy crawl-dispatch
```

- [ ] **Step 10: 첫 크롤 실행 + 실측 확인**

```bash
# 관리자 UI 의 크롤 소스 탭에서 "수동 실행" 또는 dispatch 직접 호출
psql "$PROD_READONLY_URL" -c \
  "select org_code, division_code, count(*), max(rank_points)
   from public.org_rankings group by 1,2 order by 1,2;"
```

Expected: 광주·전남 각 7개 부서에 행이 있고, 0점 행이 없다. 부서별 행 수가 협회 화면의 "점수 있는 선수 수"와 대략 일치한다.

---

## Task 4: 매칭 — 후보 조회 + 클레임 RPC

**Files:**
- Create: `supabase/migrations/<타임스탬프>_org_ranking_claim_rpc.sql`
- Create: `supabase/tests/database/019_org_ranking_claim.test.sql`

**Interfaces:**
- Consumes: Task 2의 두 테이블
- Produces: `public.my_ranking_candidates()` → `setof record (org_code text, division_code text, rank int, player_name text, org_player_id text, club_raw text, total_points int)`. 앱이 이걸 호출해 "본인인가요?" 카드를 띄운다

- [ ] **Step 1: 브랜치 + 기존 SECURITY DEFINER 관례 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-claim origin/main
cat supabase/tests/database/007_security_definer_acl.test.sql | head -40
```

`SECURITY DEFINER` 함수에 요구되는 `set search_path` 등의 관례를 기록한다.

- [ ] **Step 2: 실패하는 pgTAP 테스트를 먼저 쓴다**

`supabase/tests/database/019_org_ranking_claim.test.sql`:

```sql
begin;
select plan(5);

select has_function('public', 'my_ranking_candidates', '후보 조회 함수 존재');

-- 시드
insert into auth.users (id, email)
values ('33333333-3333-3333-3333-333333333333', 'c@test.local')
on conflict do nothing;
insert into public.users (id, name, division_codes)
values ('33333333-3333-3333-3333-333333333333', '김평화', array['gj_m_gold'])
on conflict (id) do update set name = excluded.name, division_codes = excluded.division_codes;

insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 1, '김평화',   'vudghk2116', '어등산/', 2649, 2649, 'https://x'),
  ('gj', 'gj_m_gold', 2, '이기영',   'lkybks',     '전라/',   2562, 2562, 'https://x'),
  ('gj', 'gj_w_rookie', 1, '김평화', 'other',      '다른부서/', 100, 100, 'https://x');

set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

-- 이름 + 내 부서가 맞는 행만 후보로 나온다
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  1, '이름·부서가 맞는 후보 1건만');

select is(
  (select org_player_id from public.my_ranking_candidates()),
  'vudghk2116', '후보의 협회 아이디가 맞다');

reset role;
reset request.jwt.claims;

-- 이미 confirmed 된 선수는 후보에서 빠진다
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'vudghk2116', '33333333-3333-3333-3333-333333333333', 'confirmed');

set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  0, '이미 연결된 선수는 후보에서 제외');
reset role;
reset request.jwt.claims;

-- 이름이 없는 유저는 후보가 0건이어야 한다 (전체 명단이 새지 않는다)
insert into auth.users (id, email)
values ('44444444-4444-4444-4444-444444444444', 'd@test.local')
on conflict do nothing;
insert into public.users (id, name, division_codes)
values ('44444444-4444-4444-4444-444444444444', null, array['gj_m_gold'])
on conflict (id) do update set name = null;

set local role authenticated;
set local request.jwt.claims to '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  0, '이름 없는 유저에게 명단이 새지 않는다');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
```

- [ ] **Step 3: 테스트가 실패하는 것을 확인한다**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/019_org_ranking_claim.test.sql
```

Expected: FAIL — `my_ranking_candidates` 함수가 없다

- [ ] **Step 4: RPC 작성**

`supabase/migrations/<타임스탬프>_org_ranking_claim_rpc.sql`:

```sql
-- 랭킹 후보 조회
--
-- 무언(silent) 자동 매칭을 하지 않는 이유: 협회 개인 페이지가 전체 공개라
--   "본인만 아는 정보"로 검증할 수단이 없고, 오매칭 결과가 실명 자동 공개라
--   오류 비용이 비대칭적으로 크다. 후보만 제시하고 확정은 본인 원탭 + 관리자 승인.
--
-- 협회 데이터에 생년월일이 없어(개인 성적검색 입력이 이름 하나뿐) 매칭 요소는
--   이름 + 소속 협회 + 등록 부서 셋뿐이다.

begin;

create or replace function public.my_ranking_candidates()
returns table (
  org_code      text,
  division_code text,
  rank          int,
  player_name   text,
  org_player_id text,
  club_raw      text,
  total_points  int
)
language sql
stable
security invoker
set search_path = public
as $$
  select r.org_code, r.division_code, r.rank, r.player_name,
         r.org_player_id, r.club_raw, r.total_points
  from public.org_rankings r
  join public.users u on u.id = (select auth.uid())
  where u.name is not null
    and r.player_name = u.name
    and r.org_player_id is not null
    and r.division_code = any(u.division_codes)
    -- 이미 누군가와 연결 확정된 선수는 후보에서 제외
    and not exists (
      select 1 from public.org_player_links l
      where l.org_code = r.org_code
        and l.org_player_id = r.org_player_id
        and l.status = 'confirmed'
    )
    -- 내가 이미 신청한 것도 제외
    and not exists (
      select 1 from public.org_player_links l
      where l.org_code = r.org_code
        and l.org_player_id = r.org_player_id
        and l.user_id = (select auth.uid())
    );
$$;

comment on function public.my_ranking_candidates is
  '내 이름·등록 부서와 일치하는 협회 랭킹 행을 후보로 제시한다. security invoker 라 org_rankings RLS 를 그대로 통과한다(로그인 필수).';

grant execute on function public.my_ranking_candidates to authenticated;

commit;
```

`security invoker`인 이유: 호출자의 권한으로 `org_rankings`를 읽으므로 RLS가 그대로 적용된다. `definer`로 만들면 anon에게도 명단이 새는 경로가 열린다.

- [ ] **Step 5: 테스트가 통과하는 것을 확인한다**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/019_org_ranking_claim.test.sql
```

Expected: PASS 5/5

- [ ] **Step 6: 변이 주입으로 역검증**

`and r.division_code = any(u.division_codes)` 줄을 잠시 지우고 `supabase db reset` 후 재실행한다.

Expected: "이름·부서가 맞는 후보 1건만" 단언이 **실패**(2건이 나온다)해야 한다. 확인 후 원복한다.

- [ ] **Step 7: 커밋 & PR**

```bash
git add supabase/migrations supabase/tests/database/019_org_ranking_claim.test.sql
git commit -m "feat(db): 랭킹 후보 조회 RPC

이름 + 등록 부서로 후보만 제시한다. 확정은 본인 원탭 + 관리자 승인.
security invoker 라 org_rankings RLS 를 그대로 통과한다 — definer 로 만들면
anon 에게 명단이 새는 경로가 열린다.

협회에 생년월일이 없어 매칭 요소는 이름·협회·부서 셋뿐이다."
git push -u origin feature/JY-ranking-claim
gh pr create --fill
```

---

## Task 5: 관리자 승인 큐

**Files:**
- Create: `app/lib/models/org_ranking.dart`
- Create: `app/lib/screens/admin/ranking_claims_tab.dart`
- Create: `app/test/ranking_claims_test.dart`
- Modify: `app/lib/screens/admin/admin_shell.dart` (탭 추가)

**Interfaces:**
- Consumes: Task 2의 `org_player_links`
- Produces: `RankingClaim` 모델 (`orgCode`, `orgPlayerId`, `playerName`, `divisionCode`, `rank`, `clubRaw`, `claimantName`, `claimantId`, `claimedAt`), `groupClaimsByPlayer(List<RankingClaim>) → List<ClaimGroup>` — Task 6이 모델을 재사용한다

- [ ] **Step 1: 브랜치 + 기존 탭 패턴 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-admin-queue origin/main
sed -n '1,60p' app/lib/screens/admin/crawl_sources_tab.dart
grep -n "Tab\|tabs" app/lib/screens/admin/admin_shell.dart | head -20
```

`crawl_sources_tab.dart`는 데이터를 주입받는 `StatelessWidget` 카드(`SourceCard`)와 로딩·에러를 다루는 상위 위젯으로 나뉘어 있다. **같은 구조를 따라야 네트워크 없이 테스트된다.**

- [ ] **Step 2: 모델 + 그룹화 함수 테스트를 먼저 쓴다**

`app/test/ranking_claims_test.dart`:

```dart
import 'package:allround/models/org_ranking.dart';
import 'package:allround/screens/admin/ranking_claims_tab.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

RankingClaim _claim({
  required String orgPlayerId,
  required String claimantName,
  required String claimantId,
}) {
  return RankingClaim(
    orgCode: 'gj',
    orgPlayerId: orgPlayerId,
    playerName: '김평화',
    divisionCode: 'gj_m_gold',
    rank: 1,
    clubRaw: '어등산/',
    claimantName: claimantName,
    claimantId: claimantId,
    claimedAt: DateTime(2026, 8, 3),
  );
}

void main() {
  test('같은 협회 선수에 대한 클레임은 한 묶음이 된다', () {
    final groups = groupClaimsByPlayer([
      _claim(orgPlayerId: 'vudghk2116', claimantName: '김평화', claimantId: 'u1'),
      _claim(orgPlayerId: 'vudghk2116', claimantName: '동명이인', claimantId: 'u2'),
      _claim(orgPlayerId: 'lkybks', claimantName: '이기영', claimantId: 'u3'),
    ]);

    expect(groups.length, 2);
    final contested = groups.firstWhere((g) => g.orgPlayerId == 'vudghk2116');
    expect(contested.claimants.length, 2);
    expect(contested.isContested, isTrue);
  });

  test('신청자가 하나면 경합이 아니다', () {
    final groups = groupClaimsByPlayer([
      _claim(orgPlayerId: 'lkybks', claimantName: '이기영', claimantId: 'u3'),
    ]);

    expect(groups.single.isContested, isFalse);
  });

  testWidgets('경합 묶음은 신청자를 모두 보여준다', (tester) async {
    final group = groupClaimsByPlayer([
      _claim(orgPlayerId: 'vudghk2116', claimantName: '김평화', claimantId: 'u1'),
      _claim(orgPlayerId: 'vudghk2116', claimantName: '동명이인', claimantId: 'u2'),
    ]).single;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ClaimGroupCard(
              group: group,
              onApprove: (_) {},
              onReject: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('김평화'), findsWidgets);
    expect(find.text('동명이인'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/ranking_claims_test.dart
```

Expected: FAIL — `org_ranking.dart` 와 `ranking_claims_tab.dart` 가 없다

- [ ] **Step 4: 모델 작성**

`app/lib/models/org_ranking.dart`:

```dart
/// 협회 랭킹 한 행. 협회가 공표한 값 그대로이며 앱이 계산한 값이 아니다.
class OrgRankingRow {
  const OrgRankingRow({
    required this.orgCode,
    required this.divisionCode,
    required this.rank,
    required this.playerName,
    required this.rankPoints,
    required this.totalPoints,
    this.orgPlayerId,
    this.clubRaw,
  });

  final String orgCode;
  final String divisionCode;
  final int rank;
  final String playerName;
  final int rankPoints;
  final int totalPoints;
  final String? orgPlayerId;
  final String? clubRaw;

  factory OrgRankingRow.fromJson(Map<String, dynamic> j) {
    return OrgRankingRow(
      orgCode: j['org_code'] as String,
      divisionCode: j['division_code'] as String,
      rank: j['rank'] as int,
      playerName: j['player_name'] as String,
      rankPoints: j['rank_points'] as int,
      totalPoints: j['total_points'] as int,
      orgPlayerId: j['org_player_id'] as String?,
      clubRaw: j['club_raw'] as String?,
    );
  }
}

/// 협회 선수에 대한 계정 연결 신청 1건.
class RankingClaim {
  const RankingClaim({
    required this.orgCode,
    required this.orgPlayerId,
    required this.playerName,
    required this.divisionCode,
    required this.rank,
    required this.claimantName,
    required this.claimantId,
    required this.claimedAt,
    this.clubRaw,
  });

  final String orgCode;
  final String orgPlayerId;
  final String playerName;
  final String divisionCode;
  final int rank;
  final String claimantName;
  final String claimantId;
  final DateTime claimedAt;
  final String? clubRaw;
}

/// 같은 협회 선수를 놓고 겨루는 신청들의 묶음.
class ClaimGroup {
  const ClaimGroup({
    required this.orgCode,
    required this.orgPlayerId,
    required this.playerName,
    required this.divisionCode,
    required this.rank,
    required this.claimants,
    this.clubRaw,
  });

  final String orgCode;
  final String orgPlayerId;
  final String playerName;
  final String divisionCode;
  final int rank;
  final List<RankingClaim> claimants;
  final String? clubRaw;

  /// 한 선수에 신청이 둘 이상 — 관리자가 골라야 한다.
  bool get isContested => claimants.length > 1;
}
```

- [ ] **Step 5: 그룹화 함수 + 카드 위젯 작성**

`app/lib/screens/admin/ranking_claims_tab.dart` 에 먼저 순수 함수와 카드를 넣는다. 네트워크를 타는 상위 위젯은 그 다음이다.

```dart
/// pending 클레임을 협회 선수 단위로 묶는다. 경합을 관리자가 보게 하는 것이
/// 이 화면의 존재 이유이므로, 묶기는 순수 함수로 두어 테스트로 고정한다.
List<ClaimGroup> groupClaimsByPlayer(List<RankingClaim> claims) {
  final byPlayer = <String, List<RankingClaim>>{};
  for (final c in claims) {
    byPlayer.putIfAbsent('${c.orgCode}/${c.orgPlayerId}', () => []).add(c);
  }
  return byPlayer.values.map((group) {
    final first = group.first;
    return ClaimGroup(
      orgCode: first.orgCode,
      orgPlayerId: first.orgPlayerId,
      playerName: first.playerName,
      divisionCode: first.divisionCode,
      rank: first.rank,
      clubRaw: first.clubRaw,
      claimants: group,
    );
  }).toList();
}
```

`ClaimGroupCard` 는 `SourceCard`(`crawl_sources_tab.dart:6`) 패턴을 따른다 — `StatelessWidget`, 데이터와 콜백(`onApprove`, `onReject`)을 주입받고 자체 네트워크 호출은 하지 않는다. 표시할 것:

- 협회 선수: 부서 라벨 · 순위 · 성명 · 소속
- 신청자 목록: 각 신청자의 이름과 신청 시각. **경합이면 전부 보인다**
- 신청자마다 승인 / 반려 버튼

- [ ] **Step 6: 상위 위젯 + 승인 처리**

`pending` 조회와 승인·반려 mutation을 담당하는 상위 위젯을 작성하고 `admin_shell.dart` 에 탭으로 등록한다.

- 승인: `status='confirmed'`, `decided_at=now()`, `decided_by=<현재 관리자 id>` 를 함께 쓴다
- 승인이 유니크 인덱스 위반(Postgres `23505`)으로 실패하면 **"이미 다른 사람에게 연결된 선수입니다"** 로 안내한다. 이건 정상 동작이지 버그가 아니다
- `dynamic` 대신 명시적 타입을 쓴다. **`dart format` 실행 금지** — 주변 스타일에 손으로 맞춘다

- [ ] **Step 7: 테스트 통과 확인 + 전체 테스트**

```bash
cd app && flutter analyze && flutter test
```

Expected: analyze 무경고(warning도 CI에서 에러다), 전체 테스트 PASS

- [ ] **Step 8: 실기기 확인**

```bash
cd app && flutter run --release
```

iPhone 실기기는 `--release` 필수다(debug는 ProMotion+iOS26 크래시). 관리자 계정으로 로그인해 탭이 뜨고 승인·반려가 동작하는지 확인한다.

- [ ] **Step 9: 커밋 & PR**

```bash
git add app/lib/screens/admin app/test
git commit -m "feat(admin): 랭킹 클레임 승인 큐

같은 협회 선수에 pending 이 여럿이면 한 묶음으로 보여준다 — 경합을
관리자가 보고 고르는 것이 이 화면의 존재 이유다.

승인이 유니크 인덱스 위반으로 실패하면 '이미 다른 사람에게 연결됨'으로 안내."
git push -u origin feature/JY-ranking-admin-queue
gh pr create --fill
```

---

## Task 6: 랭킹 화면

**Files:**
- Create: `app/lib/screens/rankings/rankings_screen.dart`
- Create: `app/lib/screens/rankings/ranking_claim_card.dart`
- Modify: 네비게이션 진입점 (Step 1에서 확인)

**Interfaces:**
- Consumes: Task 2의 `org_rankings`, Task 4의 `my_ranking_candidates()`, **Task 5의 `OrgRankingRow` 모델**(`app/lib/models/org_ranking.dart`)
- Produces: 유저가 보는 랭킹 화면. 위젯 `RankingList`, `RankingSourceNotice`, `RankingClaimPrompt`

**Task 5가 먼저 머지되어야 한다** — 모델 파일을 공유한다.

- [ ] **Step 1: 브랜치 + 진입점·화면 패턴 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-screen origin/main
ls app/lib/screens/tournaments/
grep -rn "MoreScreen\|more_screen" app/lib/ | grep -i "route\|nav" | head
```

기존 목록 화면(로딩·빈 상태·에러 처리)의 패턴과, 새 화면을 어디에 붙일지(더보기 탭 등)를 정한다.

- [ ] **Step 2: 위젯 테스트를 먼저 쓴다**

`app/test/rankings_screen_test.dart`:

```dart
import 'package:allround/models/org_ranking.dart';
import 'package:allround/screens/rankings/rankings_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OrgRankingRow _row({
  required int rank,
  required String name,
  required int points,
  String? orgPlayerId,
}) {
  return OrgRankingRow(
    orgCode: 'gj',
    divisionCode: 'gj_m_gold',
    rank: rank,
    playerName: name,
    rankPoints: points,
    totalPoints: points,
    orgPlayerId: orgPlayerId,
    clubRaw: '어등산/',
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('순위표 행이 렌더링된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: null,
      ),
    );

    expect(find.text('김평화'), findsOneWidget);
    expect(find.text('이기영'), findsOneWidget);
  });

  testWidgets('출처 표기가 항상 보인다', (tester) async {
    await _pump(tester, const RankingSourceNotice(orgLabel: '광주광역시테니스협회'));

    expect(find.textContaining('광주광역시테니스협회'), findsOneWidget);
    expect(find.textContaining('협회 공표가 우선'), findsOneWidget);
  });

  testWidgets('내 계정과 연결된 행은 강조된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: 'vudghk2116',
      ),
    );

    expect(find.byKey(const ValueKey('ranking-row-mine')), findsOneWidget);
  });

  testWidgets('후보가 있으면 클레임 카드가 뜬다', (tester) async {
    await _pump(
      tester,
      RankingClaimPrompt(
        candidate: _row(
          rank: 12,
          name: '김평화',
          points: 340,
          orgPlayerId: 'vudghk2116',
        ),
        onClaim: () {},
      ),
    );

    expect(find.textContaining('본인'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 테스트가 실패하는 것을 확인한다**

```bash
cd app && flutter test test/rankings_screen_test.dart
```

Expected: FAIL — `rankings_screen.dart` 가 없다

- [ ] **Step 4: 화면 구현**

`app/lib/screens/rankings/rankings_screen.dart` 에 위 테스트가 요구하는 위젯 셋을 먼저 만들고(전부 데이터 주입형 `StatelessWidget`), 그 위에 조회를 담당하는 화면을 얹는다.

- `RankingList({required List<OrgRankingRow> rows, required String? linkedOrgPlayerId})`
  — 순위 · 성명 · 소속 · 순위포인트 · 전체포인트. `row.orgPlayerId == linkedOrgPlayerId` 인 행에
  `key: ValueKey('ranking-row-mine')` 를 주고 강조 스타일을 입힌다
- `RankingSourceNotice({required String orgLabel})`
  — `"$orgLabel 공표 데이터 · 참고용이며 협회 공표가 우선합니다"`. **상시 노출**이다.
  앱이 계산한 값이 아니라는 것을 화면이 스스로 말해야 한다
- `RankingClaimPrompt({required OrgRankingRow candidate, required VoidCallback onClaim})`
  — `"골드부 12위 김평화(어등산) — 본인인가요?"` + 신청 버튼

화면 본체가 담당할 것:
- **협회 선택**(광주 / 전남) + **부서 선택**(랭킹 부서 7개). 협회별 분리 운영이라 통합 뷰는 만들지 않는다
- `my_ranking_candidates()` 호출 결과가 있으면 상단에 `RankingClaimPrompt`
- 신청 후에는 "확인 중입니다" 상태로 바뀐다(`org_player_links` 에 본인 `pending` 이 있는 경우)

`dynamic` 금지. **`dart format` 실행 금지** — 주변 스타일에 손으로 맞춘다.

- [ ] **Step 5: 테스트 통과 확인 + 전체 테스트**

```bash
cd app && flutter analyze && flutter test
```

Expected: analyze 무경고, 전체 PASS. **부분 테스트만 돌리지 않는다** — 로컬 Flutter가 CI SDK보다 구버전이라 전체를 돌려야 컴파일 차이가 잡힌다.

- [ ] **Step 6: 진입점 연결**

Step 1에서 정한 위치(더보기 탭 등)에 랭킹 화면을 연결한다. 네비게이션을 건드리므로 `app_bottom_nav_test.dart` 가 깨지지 않는지 확인한다.

- [ ] **Step 7: 웹빌드 색인 차단 확인**

랭킹 경로가 검색엔진에 색인되지 않도록 `robots.txt` 또는 메타 태그를 확인한다.

```bash
grep -n "^web:" -A 6 Makefile
ls app/web/
cat app/web/robots.txt 2>/dev/null || echo "robots.txt 없음 — 생성 필요"
```

`app/web/robots.txt` 가 없으면 `User-agent: *` / `Disallow: /` 로 만든다. **`make web` 은 로컬 전용이고 프로덕션 배포가 아니지만**, 웹빌드를 어디든 올리는 순간 실명 명단이 색인 대상이 된다.

- [ ] **Step 8: 실기기 확인 + 커밋**

```bash
cd app && flutter run --release
git add app/lib/screens/rankings app/test
git commit -m "feat(app): 협회 랭킹 화면

협회·부서 선택 후 공표 순위표를 보여준다. 앱이 계산한 값이 아니므로
'협회 공표 데이터 · 참고용, 협회 공표가 우선' 표기를 상시 노출한다.

후보가 있으면 클레임 카드로 본인 확인을 받는다."
git push -u origin feature/JY-ranking-screen
gh pr create --fill
```

---

## Task 7: 개인정보 문서 — 출시 블로커

**코드가 아니라 정책이다. 이게 없으면 랭킹을 켜면 안 된다.**

**Files:**
- Modify: 개인정보처리방침 (Step 1에서 실제 경로 확인)
- Create/Modify: 삭제(이의) 요청 창구

- [ ] **Step 1: 현행 처리방침 위치 확인**

```bash
git fetch origin && git checkout -b feature/JY-ranking-privacy origin/main
grep -rln "개인정보처리방침\|privacy" docs/ app/lib/ supabase/ --include="*.md" --include="*.dart" --include="*.sql" | head -10
```

- [ ] **Step 2: 처리방침에 랭킹 항목 추가**

담아야 할 것:
- 수집 항목: 협회가 공표한 성명·소속·순위·포인트
- 수집 출처: 광주광역시테니스협회·전라남도테니스협회 공표 자료 (협회 동의 하)
- 이용 목적: 랭킹 정보 제공
- 보유 기간: 협회 공표가 유지되는 동안. 갱신 시 이전 데이터는 대체됨
- 정보주체 권리: 삭제·정정 요청 방법과 창구

법 §30 미비 시 과태료 1천만원이다.

- [ ] **Step 3: 삭제(이의) 요청 창구 구현**

앱 미가입자도 접근 가능해야 의미가 있다. 최소 형태로 충분하다 — 문의 이메일 주소를 처리방침과 랭킹 화면 하단에 명시하고, 요청이 오면 관리자가 해당 행을 지우는 운영 절차를 문서화한다. 법 §36은 창구의 존재를 요구한다.

- [ ] **Step 4: 탈퇴 경로 확인**

```bash
grep -rn "org_player_links" supabase/functions/delete-account/ || \
  echo "on delete cascade 로 자동 소멸 — 별도 코드 불필요"
```

`user_id`에 `on delete cascade`가 걸려 있어 링크는 자동 소멸한다. **미러의 실명 행은 남는다**(협회가 여전히 공표 중이므로 탈퇴자는 미가입 선수와 같은 취급). 이 동작이 의도된 것임을 `delete-account` 주석에 남긴다.

- [ ] **Step 5: 커밋 & PR**

```bash
git add docs app
git commit -m "docs(privacy): 협회 공표 랭킹 표시 항목 추가

수집 출처·목적·보유기간·삭제 요청 창구 명시(법 §30·§36).
탈퇴 시 계정 연결은 cascade 로 소멸하나 미러의 실명 행은 남는다 —
협회가 여전히 공표 중이므로 탈퇴자는 미가입 선수와 같은 취급."
git push -u origin feature/JY-ranking-privacy
gh pr create --fill
```

---

## 완료 판정

전부 머지된 뒤:

```bash
# 1. 크롤이 실제로 돌았는가
psql "$PROD_READONLY_URL" -c \
  "select org_code, division_code, count(*) rows, max(fetched_at) last_fetch
   from public.org_rankings group by 1,2 order by 1,2;"

# 2. 0점 행이 없는가 (개인정보 최소화가 실제로 동작하는가)
psql "$PROD_READONLY_URL" -c \
  "select count(*) from public.org_rankings where rank_points = 0 and total_points = 0;"
# Expected: 0

# 3. anon 이 정말 못 읽는가
curl -s "$SUPABASE_URL/rest/v1/org_rankings?select=player_name&limit=1" \
  -H "apikey: $ANON_KEY" | head -c 200
# Expected: 빈 배열 [] — 행이 새면 실패

# 4. 원본이 보관되는가
# Supabase Studio → Storage → ranking-snapshots 버킷에 org/division/날짜.html 존재 확인

# 5. 하네스 전체
bash scripts/harness/run_all.sh
```

---

## 이 계획이 다루지 않는 것

| 항목 | 언제 |
|---|---|
| 배점 계산 로직 | 협회 제휴 심화 후. `gj-2026.json` 은 이미 정형화돼 있다 |
| 대회별 입상 원천 (`tournament_results`) | 계산 단계. 그때 협회에서 정식으로 받는다 |
| 순위 변동 추이 | 요구사항 없음. 원본 아카이브로 소급 생성 가능 |
| KTA·KATO·전북 | 광주·전남 파일럿 성과 확인 후 |
| 연말 리셋 대응 자동화 | 2026년 12월 전까지. 지금은 원본 보관이 유일한 보험이다 |
