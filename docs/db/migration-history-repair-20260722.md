# 마이그레이션 이력 정합화 런북 (2026-07-22)

> **상태: 완료 (2026-07-22).** 프로덕션(`bsjdgwmveokanclqwtvx`) 이력 정합화를
> 실행했다. 이력 테이블만 변경했고 스키마·데이터는 건드리지 않았다.
>
> | 항목 | 실행 전 | 실행 후 |
> |---|---|---|
> | `schema_migrations` 행수 | 131 | **127** |
> | version 불일치 | 83 (로컬 75 + 원격 79) | **0** |
> | `db push --dry-run` | `Remote migration versions not found…` (거부) | **`Remote database is up to date.`** |
>
> 사후 확인: `public` 테이블 42개·대회 81건·유저 22명·cron 6개 변동 없음.
> `close_expired_tournaments()` 는 여전히 부재 — repair 가 SQL 을 실행하지 않았음을 확인.
>
> 백업(실행 전 스냅샷): `docs/db/schema_migrations_snapshot_20260722.tsv` (version+name).
> 지문 `md5(version|name) = 3bfb535a4252241d3bb148567e15eed3`.
>
> ⚠️ **SQL 본문 아카이브는 리포에 커밋하지 않는다.** 삭제된 79행 중
> `20260523102723_fix_cron_invoke_hardcode` 와 `20260525062934_029_fix_invoke_edge_function_key`
> 에 **service_role JWT 가 평문으로 들어 있다**(이미 알려진 노출 건, `docs/security/cron-jwt-rotation.md`).
> 이 리포는 PUBLIC 이므로 아카이브는 리포 밖 비공개 위치에 보관한다.
> 필요하면 `supabase migration fetch --linked --workdir <비공개경로>` 로 재생성한다
> — 단 정합화 이후에는 삭제된 79행이 더 이상 원격에 없다.

## 1. 실행 전 상태 (실측)

`supabase migration list --linked` 기준.

| 구분 | 건수 |
|---|---|
| 로컬 파일 | 128 (CLI 인식 127 + 이름규칙 위반 `046b` 1) |
| 원격 이력 행 | 131 |
| version 정합 | 52 |
| 로컬에만 있는 version | 75 |
| 원격에만 있는 version | 79 |

### 실행 전 `db push` 는 **거부** 상태였다

dry-run 결과 재적용을 시도하지 않고 아래로 끝난다:

```
Remote migration versions not found in local migrations directory.
```

즉 fail-safe 였다. "83개를 다시 적용한다"는 위험은 실현되지 않았다.
다만 `db push` 를 전혀 쓸 수 없으므로 JY-116 우회(`apply_migration` 직접 적용)가
계속 강제되고, 그 우회가 다시 version 을 어긋나게 만드는 악순환이다.

### 어긋난 원인

`apply_migration` (MCP) 은 **호출 시각**으로 version 을 새로 만들고 name 에
로컬 파일명을 접미/접두로 붙인다. 그래서 파일명 version 과 영영 다르다.

| 로컬 | 원격 기록 |
|---|---|
| `20260716180000_respond_club_event_capacity.sql` | `20260716111749_ugc_20260716180000_respond_club_event_capacity` |
| `20260719010000_isolate_device_push_tokens.sql` | `20260719055646_isolate_device_push_tokens_20260719010000` |
| `029_division_codes_reset_eligible_grades.sql` | `20260525062425_028_division_codes_reset_eligible_grades` |

## 2. 판정 결과

원격 `statements`(실제 적용된 SQL)를 `supabase migration fetch` 로 131건 전부
받아 로컬 파일과 내용 대조했다. 주석은 원격 저장 시 제거되므로 정규화 후 비교.

| 판정 | 건수 | 의미 |
|---|---|---|
| 정합 | 52 | version·내용 모두 일치 |
| 적용됨 (version 불일치) | 54 | 내용 일치, version 만 다름 → `--status applied` 안전 |
| 적용됨 · 이후 로컬 파일 수정 | 16 | 적용 후 파일이 편집됨. 재적용 금지 |
| **기록 없음** | **6** | 어떤 원격 행과도 이름·내용이 안 맞음 → §4 확인 필요 |

## 3. 실행 절차 (2026-07-22 실행 완료)

### 3-0. 원격 SQL 원본 백업 (필수 선행)

`--status reverted` 는 행을 **삭제**한다. 그 행의 `statements` 가 "프로덕션에
실제로 무엇이 실행됐는지"에 대한 유일한 기록이므로 먼저 리포에 보존한다.

```bash
supabase migration fetch --linked --workdir <비공개경로>
tar czf <비공개경로>/schema_migrations_statements_20260722.tar.gz \
  -C <비공개경로>/supabase migrations
```

> ⚠️ 이 아카이브를 **리포에 커밋하지 말 것.** 원격 기록 중 일부에 service_role JWT 가
> 평문으로 들어 있고 이 리포는 PUBLIC 이다. 리포에는 version+name 인덱스(TSV)만 넣는다.

### 3-1. 로컬 파일 version 을 applied 로 등록 (75건)

먼저 **1건만 카나리로** 실행해 CLI 가 `027` 같은 비-타임스탬프 version 을
받아들이는지 확인한다(001~026 이 그 형식으로 이미 들어 있으니 테이블 자체는
허용한다. 확인 대상은 CLI 인자 검증이다).

```bash
supabase migration repair --linked --status applied 027
supabase migration list --linked | grep ' 027 '   # Local/Remote 양쪽에 027 이 떠야 한다
```

통과하면 나머지를 한 번에 넣는다.


```bash
supabase migration repair --linked --status applied \
  027   028   029   030   031   032   033   034   035   036   037   038   039   040   \
041   042   043   044   045   046   047   048   049   050   051   052   053   054   055 \
  056   057   058   059   060   061   062   063   064   065   066   067   068   069   \
070   071   072   073   074   075   076   077   078   079   080   081   20260713120000  \
 20260714140000   20260715090000   20260716180000   20260716210000   20260716211500   \
20260717163946   20260717191744   20260717195358   20260718030000   20260719010000   \
20260719010238   20260719011000   20260719012000   20260719013000   20260719014000   \
20260719015000   20260719061745   20260719062942   20260719065613
```

### 3-2. 레거시 원격 version 제거 (79건)

```bash
supabase migration repair --linked --status reverted \
  20260523102723   20260525062425   20260525062934   20260525063632   20260525064337   \
20260525235451   20260526113715   20260527000941   20260528013037   20260528023917   \
20260528084651   20260528084710   20260528084725   20260528084740   20260602033214   \
20260604052417   20260604055555   20260605110641   20260605111048   20260605111213   \
20260605113859   20260605114020   20260605121844   20260607081845   20260609124003   \
20260610065316   20260610065341   20260611011045   20260614234402   20260614234417   \
20260614234433   20260614234504   20260614234524   20260614234541   20260614234601   \
20260614234613   20260617015257   20260617023558   20260617023919   20260617033337   \
20260617033555   20260617040624   20260617040750   20260617044401   20260618011832   \
20260623235211   20260624003814   20260624011757   20260624021639   20260624055422   \
20260624095313   20260624101208   20260707070949   20260707121940   20260708050720   \
20260708064304   20260708065158   20260709023724   20260716111223   20260716111320   \
20260716111416   20260716111717   20260716111749   20260717081952   20260717101803   \
20260717105417   20260719055627   20260719055646   20260719055655   20260719055702   \
20260719055719   20260719055728   20260719055736   20260719055745   20260719063717   \
20260719065312   20260719070125   20260721101349   20260721101418
```

### 3-3. 검증

```bash
supabase migration list --linked   # Local/Remote 두 열이 127행 모두 일치해야 한다
                                   # (046b 는 CLI 가 건너뛰므로 목록에 안 나온다)
supabase db push --linked --dry-run   # 출력에 적용 대상이 없어야 한다
```

> `046b_seed_futsal_venues.sql` 은 파일명 규칙(`<timestamp>_name.sql`) 위반이라
> CLI 가 항상 **건너뛴다**. 원격에는 `20260605111048/111213` 2배치로 이미 적용돼
> 있다. 이름을 고치면 `db push` 가 재적용을 시도하므로 **고치지 말 것**.

## 4. 기록 없던 6건 — 프로덕션 조회로 확정

이 6건은 원격 이력 어디에도 대응 기록이 없다. **프로덕션에 직접 조회해 확정했다**
(2026-07-22, 읽기전용). 결과는 아래 "실제 상태" 열.

| 파일 | 실제 상태 (프로덕션 조회) |
|---|---|
| `027` | **미적용 확정** — `close_expired_tournaments()` 없음, `crawl_sources.id` 기본값이 아직 `uuid_generate_v7()`, `close-expired-tournaments-daily` cron 없음 (3개 변경 전부 부재) |
| `028` | **미적용, 그러나 후속에 의해 무의미** — `crawl-dispatch-regular`/`-last` 없음. 적용된 `20260710010000_crawl_daily_schedule` 이 `crawl-dispatch` 단일 잡(`0 21 * * *`)으로 대체함 |
| `036` | **부분 적용** — 버킷 `club-logos` 존재(public=true), 그러나 **`clubs.logo_url` 컬럼 없음** |
| `041` | 적용됨 — `user_tennis_orgs.division_codes` 존재 |
| `042` | 적용됨 — `tournaments.manual_description` 존재 |
| `049` | 데이터 정규화라 스키마 흔적 없음. 재적용해도 멱등 |

| 파일 | 재적용하면? |
|---|---|
| `027_db_crawler_review_fixes.sql` | **위험** — 구버전 `prevent_role_self_update()` 로 되돌아가 `20260618042700`·`20260708050720` 하드닝이 무효화됨 |
| `028_adjust_crawler_schedule.sql` | 낮음 — `cron.schedule` 재등록뿐 |
| `036_club_logos.sql` | **위험** — `club_logos_public_read` 정책이 부활해 `20260719055728` 스토리지 하드닝이 무효화됨 |
| `041_fix_grade_matching.sql` | **위험/실패** — 구버전 `tournaments_for_user` 로 덮어씀. 반환타입이 `SETOF`→`TABLE` 로 바뀌었으므로 `create or replace` 자체가 에러날 가능성 높음 |
| `042_manual_description.sql` | 확정 적용됨 — `20260617044401` 이 `tournaments.manual_description` 에 UPDATE 를 수행했다(컬럼이 없으면 실패했을 DML) |
| `049_normalize_body_newlines.sql` | 낮음 — 멱등 데이터 정규화 |

**결론: 6건 모두 `--status applied` 로 등록한다.** 미적용이 확인된 `027`·`036` 도
마찬가지다 — 그 파일들은 구버전 정의를 담고 있어 지금 돌리면 이후 하드닝을 되돌린다.
빠진 기능은 **새 마이그레이션으로** 채운다(이력 조작으로 메우지 않는다).

### 후속 작업 (이력 정합화와 별건)

- **`027` — 만료 대회 자동 마감이 프로덕션에 없다.** `close_expired_tournaments()` 와
  일일 cron 이 통째로 빠져 있다. 되살릴지는 제품 판단. 되살린다면 027 재적용이 아니라
  새 마이그레이션으로, `prevent_role_self_update()` 부분은 **빼고** 작성한다.
  (`crawl_sources.id` 기본값도 아직 `uuid_generate_v7()` 이라 관리자 소스 등록 문제가
  남아 있을 수 있다 — 별도 확인 필요.)
- **`036` — `clubs.logo_url` 컬럼이 없다.** → `20260722040000_restore_clubs_logo_url.sql`
  작성 완료 (미적용). 조사 결과 로고 저장 실패보다 심각했다. 이미 적용된 두 함수가
  이 컬럼을 참조해 프로덕션에서 `42703` 으로 깨져 있다:
  - `delete_account_data()` — `supabase/functions/delete-account` 의 **계정 삭제가 실패**한다
    (개인정보보호법 §21 관련).
  - `create_ugc_report()` — 앱의 **클럽 신고가 실패**한다.

  `clubs-create/index.ts` 의 `'logo_url' column` fallback 이 로고 저장 실패만 가려서
  드러나지 않았다. 컬럼 복구 후 그 fallback 은 죽은 코드가 된다(별도 정리).

```sql
-- 027
select to_regprocedure('public.close_expired_tournaments()') is not null as fn_close_expired;
select column_default from information_schema.columns
 where table_schema='public' and table_name='crawl_sources' and column_name='id';
-- 027 / 028: cron 잡
select jobname, schedule from cron.job
 where jobname in ('close-expired-tournaments-daily','crawl-dispatch',
                   'crawl-dispatch-regular','crawl-dispatch-last');
-- 036
select 1 from information_schema.columns
 where table_schema='public' and table_name='clubs' and column_name='logo_url';
select id, public from storage.buckets where id='club-logos';
-- 041
select 1 from information_schema.columns where table_schema='public'
 and table_name='user_tennis_orgs' and column_name='division_codes';
```

## 5. 백필 확인 — 이상 없음

원격 131행 중 `statements` 가 비어 있는(`;` 뿐) 행이 정확히 하나 있다:

```
20260722030000_backfill_users_primary_region
```

`migration repair --status applied` 로 이력만 넣으면 이렇게 된다. 즉 이 
마이그레이션의 `UPDATE public.users SET primary_region = ...` 백필이 
**프로덕션에서 실제로 돌지 않았을 수 있다**. SQL Editor 로 직접 돌린 뒤 
repair 했을 수도 있으므로 아래로 확인한다.

```sql
select count(*) as not_backfilled
from public.users u
join public.user_tennis_orgs uto on uto.user_id = u.id
join public.regions r on r.code = uto.region_code and r.is_active
where u.primary_region is null;
```

**결과: 0 — 백필은 실제로 수행됐다.** SQL Editor 등으로 직접 실행한 뒤 repair 로
이력만 넣은 것으로 보인다. 조치 불필요.

## 6. 재발 방지 (결정: A)

`apply_migration` 을 다시 쓰면 또 어긋난다. **(A) 로 통일하기로 결정했고
문서 반영까지 마쳤다.**

- **(A) `db push` 로 복귀**: 이력이 파일명과 일치하므로 `db push` 가 다시
  동작한다. JY-116 의 원래 목표.
- **(B) `apply_migration` 유지 + 매번 repair**: 적용 직후 
  `repair --status reverted <새 version>` + `--status applied <파일 version>`.
  수동 단계가 늘어 실수 여지가 크다.

`docs/deploy.md` §2.2 와 `docs/rules/DATABASE_RULES.md` "마이그레이션 배포" 절을
(A) 기준으로 갱신했다.

## 7. 승인 및 실행 결과

- [x] §3 절차대로 프로덕션 이력 테이블 정합화 (75 applied + 79 reverted) — 완료
- [x] §4 6건을 `applied` 로 등록 — 완료
- [x] §6 (A) `db push` 복귀로 통일 — `docs/deploy.md` §2.2,
      `docs/rules/DATABASE_RULES.md` 갱신 완료
- [x] §4 후속 `036` — `20260722040000_restore_clubs_logo_url.sql` 작성 완료, **프로덕션 미적용**
- [ ] §4 후속 `027` — 만료 대회 자동 마감 복원 여부 (제품 판단 대기)

### 실행 중 걸린 것

`supabase migration repair` 에 version 을 넘길 때 zsh 는 따옴표 없는 변수를 단어
분리하지 않는다(bash 와 다름). `$(cat list)` 를 그대로 넘기면 전체가 한 인자로 들어가
`invalid version number` 로 실패한다(이력은 변경되지 않음). 배열로 넘겨야 한다:

```zsh
OLD=("${(@f)$(cat versions.txt)}")
supabase migration repair --linked --status reverted $OLD
```

## 부록 A. 전체 대응표 (128건)

| 로컬 파일 | 원격 기록 (version_name) | 판정 | 유사도 |
|---|---|---|---|
| `001_extensions.sql` | `001_extensions.sql` | 정합 | 0.77 |
| `002_init_users_sports.sql` | `002_init_users_sports.sql` | 정합 | 1.00 |
| `003_tournaments.sql` | `003_tournaments.sql` | 정합 | 1.00 |
| `004_clubs.sql` | `004_clubs.sql` | 정합 | 1.00 |
| `005_chat_rules.sql` | `005_chat_rules.sql` | 정합 | 1.00 |
| `006_notifications.sql` | `006_notifications.sql` | 정합 | 1.00 |
| `007_crawl_audit.sql` | `007_crawl_audit.sql` | 정합 | 1.00 |
| `008_cron.sql` | `008_cron.sql` | 정합 | 1.00 |
| `009_regions_and_multi_org.sql` | `009_regions_and_multi_org.sql` | 정합 | 1.00 |
| `010_tennis_grade_revamp.sql` | `010_tennis_grade_revamp.sql` | 정합 | 1.00 |
| `011_ensure_profile_rpc.sql` | `011_ensure_profile_rpc.sql` | 정합 | 1.00 |
| `012_rate_limit.sql` | `012_rate_limit.sql` | 정합 | 1.00 |
| `013_qa_cache.sql` | `013_qa_cache.sql` | 정합 | 1.00 |
| `014_intent_examples.sql` | `014_intent_examples.sql` | 정합 | 1.00 |
| `015_uuid_v7.sql` | `015_uuid_v7.sql` | 정합 | 1.00 |
| `016_tournaments_search_sport_filter.sql` | `016_tournaments_search_sport_filter.sql` | 정합 | 1.00 |
| `017_uuid_v7_pgcrypto_schema_fix.sql` | `017_uuid_v7_pgcrypto_schema_fix.sql` | 정합 | 1.00 |
| `018_tournament_search_by_slots.sql` | `018_tournament_search_by_slots.sql` | 정합 | 1.00 |
| `019_crawl_sources.sql` | `019_crawl_sources.sql` | 정합 | 1.00 |
| `020_dispatcher_cron_switch.sql` | `020_dispatcher_cron_switch.sql` | 정합 | 1.00 |
| `021_crawl_sources_running_flag.sql` | `021_crawl_sources_running_flag.sql` | 정합 | 1.00 |
| `022_tournament_status_rejected.sql` | `022_tournament_status_rejected.sql` | 정합 | 1.00 |
| `023_review_helpers.sql` | `023_review_helpers.sql` | 정합 | 1.00 |
| `024_crawl_sources_url_refresh.sql` | `024_crawl_sources_url_refresh.sql` | 정합 | 1.00 |
| `025_futsal_tournament_fields.sql` | `025_futsal_tournament_fields.sql` | 정합 | 1.00 |
| `026_futsal_crawl_sources.sql` | `026_futsal_crawl_sources.sql` | 정합 | 1.00 |
| `027_db_crawler_review_fixes.sql` | — | **기록 없음 ⚠** | — |
| `028_adjust_crawler_schedule.sql` | — | **기록 없음 ⚠** | — |
| `029_division_codes_reset_eligible_grades.sql` | `20260525062425_028_division_codes_reset_eligible_grades.sql` | 적용됨 (version 불일치) | 1.00 |
| `030_invoke_edge_function_internal_cron_jwt.sql` | `20260525064337_031_invoke_edge_function_internal_cron_jwt.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.68 |
| `031_club_management.sql` | `20260525235451_031_club_management.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.51 |
| `032_drop_legacy_clubs_active_policy.sql` | `20260526113715_drop_legacy_clubs_active_policy.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.38 |
| `033_fix_club_members_rls_recursion.sql` | `20260527000941_fix_club_members_rls_recursion.sql` | 적용됨 (version 불일치) | 1.00 |
| `034_invoke_edge_function_use_vault.sql` | `20260528013037_invoke_edge_function_use_vault.sql` | 적용됨 (version 불일치) | 0.97 |
| `035_club_events.sql` | `20260528023917_club_events.sql` | 적용됨 (version 불일치) | 0.97 |
| `036_club_logos.sql` | — | **기록 없음 ⚠** | — |
| `037_rate_limits.sql` | `20260528084651_037_rate_limits.sql` | 적용됨 (version 불일치) | 0.95 |
| `038_search_like_escape.sql` | `20260528084710_038_search_like_escape.sql` | 적용됨 (version 불일치) | 1.00 |
| `039_rls_hardening.sql` | `20260528084725_039_rls_hardening.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.55 |
| `040_device_token_cap.sql` | `20260528084740_040_device_token_cap.sql` | 적용됨 (version 불일치) | 0.91 |
| `041_fix_grade_matching.sql` | — | **기록 없음 ⚠** | — |
| `042_manual_description.sql` | — | **기록 없음 ⚠** | — |
| `043_rpc_v2_region_org_filters.sql` | `20260602033214_043_rpc_v2_region_org_filters.sql` | 적용됨 (version 불일치) | 1.00 |
| `044_rpc_returns_table.sql` | `20260604052417_044_rpc_returns_table.sql` | 적용됨 (version 불일치) | 1.00 |
| `045_seed_regions.sql` | `20260604055555_045_seed_regions.sql` | 적용됨 (version 불일치) | 1.00 |
| `046_venues.sql` | `20260605110641_046_venues.sql` | 적용됨 (version 불일치) | 0.91 |
| `046b_seed_futsal_venues.sql` | `20260605111048_046b_seed_futsal_venues_batch1.sql` + `20260605111213_046b_seed_futsal_venues_batch2.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.50 |
| `047_seed_futsal_rules.sql` | `20260605113859_047_seed_futsal_rules_batch0.sql` + `20260605114020_047_seed_futsal_rules_batch1.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.22 |
| `048_venues_search_rpc.sql` | `20260605121844_048_venues_search_rpc.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.86 |
| `049_normalize_body_newlines.sql` | — | **기록 없음 ⚠** | — |
| `050_drop_clubs_active_column.sql` | `20260607081845_drop_clubs_active_column.sql` | 적용됨 (version 불일치) | 1.00 |
| `051_backfill_tournaments_region_code.sql` | `20260609124003_backfill_tournaments_region_code.sql` | 적용됨 (version 불일치) | 1.00 |
| `052_recategorize_futsal_rule_articles.sql` | `20260610065316_recategorize_futsal_rule_articles.sql` | 적용됨 (version 불일치) | 1.00 |
| `053_seed_seoul_citizen_futsal_league_2026.sql` | `20260610065341_seed_seoul_citizen_futsal_league_2026.sql` | 적용됨 (version 불일치) | 1.00 |
| `054_club_favorites.sql` | `20260611011045_054_club_favorites.sql` | 적용됨 (version 불일치) | 1.00 |
| `055_users_profile_columns.sql` | `20260614234402_users_profile_columns.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.90 |
| `056_user_tennis_orgs_pk_change.sql` | `20260614234417_user_tennis_orgs_pk_change.sql` | 적용됨 (version 불일치) | 0.96 |
| `057_clubs_members_events_update.sql` | `20260614234433_clubs_members_events_update.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.51 |
| `058_club_posts.sql` | `20260614234504_club_posts.sql` | 적용됨 (version 불일치) | 0.95 |
| `059_tournament_extension_tables.sql` | `20260614234524_tournament_extension_tables.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.64 |
| `060_notifications_unified.sql` | `20260614234541_notifications_unified.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.71 |
| `061_match_records.sql` | `20260614234601_match_records.sql` | 적용됨 (version 불일치) | 0.97 |
| `062_schedule_shares.sql` | `20260614234613_schedule_shares.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.59 |
| `063_crawl_documents.sql` | `20260617015257_063_crawl_documents.sql` | 적용됨 (version 불일치) | 0.91 |
| `064_fix_tournaments_for_user_details_join.sql` | `20260617023558_064_fix_tournaments_for_user_details_join.sql` | 적용됨 (version 불일치) | 1.00 |
| `065_rate_limit_security.sql` | `20260617023919_065_rate_limit_security.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.84 |
| `066_schedule_shares_rls_fix.sql` | `20260617033337_066_schedule_shares_rls_fix.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.79 |
| `067_fk_on_delete_policy.sql` | `20260617033555_067_fk_on_delete_policy.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.17 |
| `068_drop_notifications_log_and_fk_indexes.sql` | `20260617040624_068_drop_notifications_log_and_fk_indexes.sql` | 적용됨 (version 불일치) | 0.98 |
| `069_club_posts_storage_owner_folder.sql` | `20260617040750_069_club_posts_storage_owner_folder.sql` | 적용됨 (version 불일치) | 0.97 |
| `070_trim_crawl_descriptions.sql` | `20260617044401_070_trim_crawl_descriptions.sql` | 적용됨 · 이후 로컬 파일 수정 | 0.67 |
| `071_futsal_grades_and_2026_official_events.sql` | `20260618011832_071_futsal_grades_and_2026_official_events.sql` | 적용됨 (version 불일치) | 0.97 |
| `072_fix_tennis_grade_matching.sql` | `20260623235211_072_fix_tennis_grade_matching.sql` | 적용됨 (version 불일치) | 1.00 |
| `073_tournament_regulation_fields.sql` | `20260624003814_073_tournament_regulation_fields.sql` | 적용됨 (version 불일치) | 1.00 |
| `074_tournament_regulation_body.sql` | `20260624011757_074_tournament_regulation_body.sql` | 적용됨 (version 불일치) | 1.00 |
| `075_tournaments_for_user_division_filter.sql` | `20260624021639_075_tournaments_for_user_division_filter.sql` | 적용됨 (version 불일치) | 1.00 |
| `076_tournaments_for_user_recruiting_and_date_overlap.sql` | `20260624055422_076_tournaments_for_user_recruiting_and_date_overlap.sql` | 적용됨 (version 불일치) | 1.00 |
| `077_chat_tournament_regulation_rag.sql` | `20260624095313_077_chat_tournament_regulation_rag.sql` | 적용됨 (version 불일치) | 1.00 |
| `078_chat_slot_search_consistency.sql` | `20260624101208_078_chat_slot_search_consistency.sql` | 적용됨 (version 불일치) | 1.00 |
| `079_chat_include_closed_tournaments.sql` | `20260707070949_chat_include_closed_tournaments.sql` | 적용됨 (version 불일치) | 1.00 |
| `080_fix_club_self_update_privilege_escalation.sql` | `20260707121940_fix_club_self_update_privilege_escalation.sql` | 적용됨 (version 불일치) | 1.00 |
| `081_fix_users_self_update_policy_recursion.sql` | `20260708050720_fix_users_self_update_policy_recursion.sql` | 적용됨 (version 불일치) | 1.00 |
| `082_tournament_poster_url.sql` | `082_tournament_poster_url.sql` + `20260708065158_tournament_poster_url.sql` | 정합 | 1.00 |
| `083_gemini_usage.sql` | `083_gemini_usage.sql` + `20260708064304_gemini_usage.sql` | 정합 | 1.00 |
| `087_club_event_fee_capacity.sql` | `087_club_event_fee_capacity.sql` | 정합 | 0.16 |
| `20260617123902_fix_ensure_profile_name.sql` | `20260617123902_fix_ensure_profile_name.sql` | 정합 | 1.00 |
| `20260618014932_harden_security_definer_execution.sql` | `20260618014932_harden_security_definer_execution.sql` | 정합 | 1.00 |
| `20260618042700_set_function_search_path.sql` | `20260618042700_set_function_search_path.sql` | 정합 | 0.01 |
| `20260626055521_advisor_security_perf_fixes.sql` | `20260626055521_advisor_security_perf_fixes.sql` | 정합 | 0.39 |
| `20260708071447_gemini_usage_stats.sql` | `20260708071447_gemini_usage_stats.sql` | 정합 | 1.00 |
| `20260709020930_club_posts_pinning.sql` | `20260709020930_club_posts_pinning.sql` | 정합 | 1.00 |
| `20260709090000_club_intro_images.sql` | `20260709023724_club_intro_images.sql` + `20260709090000_club_intro_images.sql` | 정합 | 1.00 |
| `20260709120000_account_deletion.sql` | `20260709120000_account_deletion.sql` | 정합 | 1.00 |
| `20260709191827_tournament_search_region_code.sql` | `20260709191827_tournament_search_region_code.sql` | 정합 | 1.00 |
| `20260710000000_users_birth_date.sql` | `20260710000000_users_birth_date.sql` | 정합 | 1.00 |
| `20260710010000_crawl_daily_schedule.sql` | `20260710010000_crawl_daily_schedule.sql` | 정합 | 1.00 |
| `20260710020000_tennis_orgs_divisions_catalog.sql` | `20260710020000_tennis_orgs_divisions_catalog.sql` | 정합 | 1.00 |
| `20260710030000_regions_17sido_crawl_source_cols.sql` | `20260710030000_regions_17sido_crawl_source_cols.sql` | 정합 | 1.00 |
| `20260710220929_expand_division_codes_equiv.sql` | `20260710220929_expand_division_codes_equiv.sql` | 정합 | 1.00 |
| `20260711002939_tennis_org_enum_to_text.sql` | `20260711002939_tennis_org_enum_to_text.sql` | 정합 | 0.98 |
| `20260713042834_seed_kato_divisions.sql` | `20260713042834_seed_kato_divisions.sql` | 정합 | 1.00 |
| `20260713120000_club_join_notifications.sql` | `20260716111223_ugc_20260713120000_club_join_notifications.sql` | 적용됨 (version 불일치) | 0.98 |
| `20260714094308_backfill_region_17sido.sql` | `20260714094308_backfill_region_17sido.sql` | 정합 | 1.00 |
| `20260714132829_users_min_age_gate.sql` | `20260714132829_users_min_age_gate.sql` | 정합 | 0.90 |
| `20260714140000_club_recruiting_posts.sql` | `20260716111320_ugc_20260714140000_club_recruiting_posts.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260715002643_delete_account_verify.sql` | `20260715002643_delete_account_verify.sql` | 정합 | 1.00 |
| `20260715052328_backfill_user_division_codes.sql` | `20260715052328_backfill_user_division_codes.sql` | 정합 | 1.00 |
| `20260715090000_club_post_comment_permissions.sql` | `20260716111416_ugc_20260715090000_club_post_comment_permissions.sql` | 적용됨 (version 불일치) | 0.99 |
| `20260715120000_ugc_moderation.sql` | `20260715120000_ugc_moderation.sql` | 정합 | 1.00 |
| `20260716180000_respond_club_event_capacity.sql` | `20260716111749_ugc_20260716180000_respond_club_event_capacity.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260716210000_club_approval_notifications.sql` | `20260721101349_club_approval_notifications.sql` | 적용됨 (version 불일치) | 0.99 |
| `20260716211500_club_inquiries.sql` | `20260721101418_club_inquiries.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260717163946_tournament_format_pipeline.sql` | `20260717081952_tournament_format_pipeline.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260717191744_format_staged_rpc.sql` | `20260717101803_format_staged_rpc.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260717195358_guard_exclude_revision.sql` | `20260717105417_guard_exclude_revision.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260718030000_night_shift_security_hardening.sql` | `20260719055627_night_shift_security_hardening_20260718030000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719010000_isolate_device_push_tokens.sql` | `20260719055646_isolate_device_push_tokens_20260719010000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719010238_enforce_pre_account_age.sql` | `20260719055655_enforce_pre_account_age_20260719010238.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719011000_isolate_and_expire_qa_cache.sql` | `20260719055702_isolate_and_expire_qa_cache_20260719011000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719012000_make_account_deletion_retryable.sql` | `20260719055719_make_account_deletion_retryable_20260719012000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719013000_harden_storage_privacy.sql` | `20260719055728_harden_storage_privacy_20260719013000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719014000_make_account_deletion_fk_safe.sql` | `20260719055736_make_account_deletion_fk_safe_20260719014000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719015000_harden_chat_message_authorship.sql` | `20260719055745_harden_chat_message_authorship_20260719015000.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719061745_restrict_security_definer_execution.sql` | `20260719063717_restrict_security_definer_execution.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719062942_harden_format_review_actions.sql` | `20260719065312_harden_format_review_actions.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260719065613_schedule_format_pending.sql` | `20260719070125_schedule_format_pending.sql` | 적용됨 (version 불일치) | 1.00 |
| `20260722020000_tournament_poster_storage.sql` | `20260722020000_tournament_poster_storage.sql` | 정합 | 1.00 |
| `20260722030000_backfill_users_primary_region.sql` | `20260722030000_backfill_users_primary_region.sql` | 정합 | 0.00 |
