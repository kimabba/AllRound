# P3 — tennis_org enum 탈출 (enum → text FK)

작성 2026-07-11 · 관련: `docs/team/REVIEW-nationwide-tennis-crawl.md`(로드맵 P3, 블로커 #1), P1 마이그레이션 `20260710020000`(tennis_orgs 표 생성), P2 `085`(매칭 일반화).

## 배경

협회 목록이 PG enum `tennis_org`(009)으로 박혀 있어, 새 협회 추가 = enum DDL + TS/Dart 배포 + **앱 스토어 심사**가 필요하다(블로커 #1). P1에서 협회 디렉터리 표 `tennis_orgs`(code PK, 10행)를 이미 시드해 뒀다. P3는 enum-타입 컬럼들이 이 표를 FK로 바라보게 전환하고 enum 타입을 제거한다.

**값 보존·앱 투명:** enum 라벨 10개(`kta,kato,kata,ktfs,kstf,kssta,kasta,gj,jn,local`)가 `tennis_orgs.code`와 1:1 동일하다. 앱은 org를 순수 문자열(`hostOrgs: List<String>`, TS `isValidTennisOrg` 하드코딩 allowlist)로 다루고, PostgREST는 enum·text 둘 다 JSON 문자열로 직렬화한다. → **앱/TS 코드 변경 불요.**

## 실측 변환 표면 (live DB 조사)

enum `tennis_org`을 실제로 참조하는 대상은 셋뿐:
1. `user_tennis_orgs.org` — 스칼라 `tennis_org`
2. `tennis_tournament_details.host_orgs` — `tennis_org[]`
3. 함수 `tournaments_for_user(...)` — 반환 `host_orgs tennis_org[]` + 본문 `p_host_org::tennis_org` 캐스트

다른 RPC(`tournament_search_by_slots`, chat 계열)는 enum을 참조하지 않는다(host_orgs 미반환). pg_depend에는 함수 의존이 안 잡히므로, enum 드롭 전 반드시 이 함수를 재생성해야 런타임 오류를 막는다.

## 결정 사항 (사용자 승인 완료)

- **① enum 타입 드롭한다** (존치 아님). 두 컬럼+함수 전환 후 미참조 상태 → `DROP TYPE`. 비가역이나 값은 text로 보존됨.
- **② `host_orgs[]`는 text[] 그대로** (배열 원소 검증 트리거 미도입). 삽입 경로(크롤러 `tournaments-submit`의 `isValidTennisOrg`, 어드민)가 이미 검증. 스칼라 `user_tennis_orgs.org`에는 FK로 확실한 무결성 확보.

## 설계 (마이그레이션 순서)

파괴성 순: 비파괴 컬럼 전환 → 함수 재생성 → 타입 드롭.

1. **`user_tennis_orgs.org` → text + FK**
   ```sql
   alter table public.user_tennis_orgs
     alter column org type text using org::text;
   alter table public.user_tennis_orgs
     add constraint user_tennis_orgs_org_fkey
     foreign key (org) references public.tennis_orgs(code);
   ```
2. **`tennis_tournament_details.host_orgs` → text[]** (기본값도 재설정)
   ```sql
   alter table public.tennis_tournament_details
     alter column host_orgs drop default;
   alter table public.tennis_tournament_details
     alter column host_orgs type text[] using host_orgs::text[];
   alter table public.tennis_tournament_details
     alter column host_orgs set default '{}'::text[];
   ```
3. **`tournaments_for_user` DROP + CREATE** — 반환 `host_orgs text[]`, 본문 `p_host_org::tennis_org` → `p_host_org`(text 비교). 시그니처(인자)는 불변; 반환 타입만 tennis_org[]→text[]. 끝에 `NOTIFY pgrst, 'reload schema'`.
4. **`DROP TYPE public.tennis_org`** — 1~3으로 하드 의존 제거 후 성공.

배열 원소 FK 불가 → host_orgs는 text[]로 두되, 필요 시 향후(P7 카탈로그화) 검증을 앱/서버 레이어에서 일원화한다(P3 범위 밖).

## 성공 기준 (검증)

1. **데이터 보존**: 전환 전후 `user_tennis_orgs.org` 값 집합·행수 동일, `tennis_tournament_details.host_orgs` 내용 동일.
2. **FK 무결성**: 기존 `org` 값 전부 `tennis_orgs.code`에 존재해 FK 추가 성공(사전 확인: 10개 라벨 = 10개 code).
3. **RPC 동등**: 5개 user에 대한 `tournaments_for_user` 결과(특히 host_orgs 배열)가 전환 전후 diff=0.
4. **필터 동작**: `p_host_org` 지정 호출이 여전히 host_orgs 필터링 정상.
5. **enum 제거**: `select count(*) from pg_type where typname='tennis_org'` = 0.

## 파일

- 신규 마이그레이션: `supabase/migrations/086_tennis_org_enum_to_text.sql`
  (컬럼 2개 전환 + FK + `tournaments_for_user` 재생성 + `NOTIFY pgrst` + `DROP TYPE`)

## 범위 밖 (명시)

- TS `isValidTennisOrg` 하드코딩 allowlist의 DB 조회 전환 → 클라이언트 카탈로그화(P7).
- host_orgs[] 원소 검증 트리거 → 도입 안 함(결정 ②).
- 신규 협회(17시도 sido 협회) 실제 추가 → 이후 파서(P5+)와 함께.

## 리스크

- 중. 컬럼 타입 변경 + 함수 재생성. 단 값 보존이고 앱 투명, live 데이터가 10개 코드로 FK 수용 확정.
- `DROP TYPE`은 비가역 → 마이그레이션 순서상 함수 재생성이 선행돼야 안전(선행 안 하면 함수가 존재하지 않는 타입 참조로 깨짐). 검증 4단계로 게이트.
- `tournaments_for_user` 반환 타입 변경이라 `CREATE OR REPLACE` 불가 → `DROP FUNCTION` 후 `CREATE`. PostgREST overload 주의 + `NOTIFY pgrst`.
