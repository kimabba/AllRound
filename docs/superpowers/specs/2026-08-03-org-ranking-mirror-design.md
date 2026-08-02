# 협회 랭킹 미러링 — 설계

작성 2026-08-03 · 레인: 드론 · 상태: 설계 확정, 구현 전

선행 문서
- 계획서: [`docs/design/ranking-points-plan.html`](../../design/ranking-points-plan.html)
- 설계 검토: [`docs/design/ranking-points-design-review.html`](../../design/ranking-points-design-review.html)
- 규정 원문: [`docs/research/tennis-ranking-point-rules.md`](../../research/tennis-ranking-point-rules.md)

---

## 1. 한 줄 요약

광주·전남 협회가 홈페이지에 공표하는 부서별 랭킹표를 그대로 우리 DB에 복사해 앱에서 보여준다.
**앱은 점수를 계산하지 않는다.** 협회 값을 그대로 옮긴다.

---

## 2. 실물 조사 결과 (2026-08-03, 직접 HTTP 확인)

광주(`gjtennis.kr`)와 전남(`jntennis.kr`)은 **동일한 CMS**를 쓴다. 경로가 같아 파서 하나로 둘 다 처리한다.

| 경로 | 내용 |
|---|---|
| `sub4_5.php?member_kind=<부서>` | 부서별 랭킹표 |
| `sub4_6.php` | 개인 성적 검색 (입력: 이름 하나) |
| `sub4_6_rank.php?userid=<협회아이디>` | 개인 대회별 이력 팝업 |
| `sub4_2.php` | 대회별 입상자목록 |
| `sub5_3.php` | 대회결과 |

### 2.1 랭킹표 실제 구조

컬럼: `순위 | 부서 | 사진 | 성명 | 소속 | 순위포인트 | 전체포인트`

```
1   골드부  (사진)  김평화  어등산/           2,649  2,649
3   골드부  (사진)  기주형  화순/토요피닉스/   1,688  1,688
588 골드부  ()      황철상  토요피닉스           0      0
```

- 광주 골드부 **588행**, 전남 골드부 **654행**. 부서 7개 → 협회당 수천 명
- **0점 선수가 대량 포함.** 입상자 명단이 아니라 **부서 등록 선수 전원 명단**이다. 점수 내림차순이다가 0점 구간은 가나다순
- `순위포인트`와 `전체포인트`가 **전 행에서 값이 같다**(차이 0건, 양 협회 모두). 규정상으로는 베스트25(순위) vs 베스트15(시상)로 달라야 한다 → 협회 확인 대상
- `소속`은 슬래시 구분 **복수 클럽**, 후행 슬래시 있음, 빈 값도 있음
- **연도·시즌·기준일 표기가 없다.** 필터도 없다. "현재 시점" 스냅샷만 존재
- **같은 사람이 양 협회에 다른 점수로 등재**된다 (김평화: 광주 2,649 / 전남 3,278, 소속도 다름). 2026년부터 분리 운영이라 정상
- HTML 안에 `player_rank('vudghk2116','골드부')` 형태로 **협회 로그인 아이디**가 들어 있다 (`vudghk2116` = "평화"의 두벌식 타이핑). 추출 가능

### 2.2 개인 이력 팝업 (이번 범위 밖)

`sub4_6_rank.php?userid=` 는 선수별 대회 이력 전량을 준다 (김평화 46건):
`대회명 | 순위 | 종목 | 포인트 | 대회일`

- 순위 표기가 **비일관**: `1`,`4`,`8`,`16` 과 `16강`,`4강`,`32강` 이 한 컬럼에 섞임
- **`종목`(출전 부서) ≠ 랭킹 `부서`**. 김평화는 골드부 랭킹인데 지동부·남자오픈부로도 출전해 포인트 획득 → 우리가 #348에서 나눈 `is_ranking_grade` 구분과 일치
- 대회일이 연도 경계를 넘어 섞임 (2026-07 ~ 2025-12)

---

## 3. 확정된 제품 결정

| # | 결정 | 결정자 |
|---|---|---|
| 1 | 이번 범위는 **공표 순위표 미러링까지**. 점수 계산 안 함 | Commander |
| 2 | 매칭은 **후보 자동 제시 + 유저 원탭 확인 + 관리자 승인** | Commander (생년월일 매칭은 데이터 부재로 폐기) |
| 3 | 매칭된 앱 유저는 **실명 자동 공개** | Commander |
| 4 | 앱 미가입 선수도 **실명 그대로 표시** | Commander |
| 5 | 광주·전남 랭킹은 **협회별 분리**. 통합 점수 안 만듦 | Commander |
| 6 | 데이터 획득은 **협회 동의 하에 크롤링** | Commander |
| 7 | 랭킹 화면은 **로그인 유저만** (anon 없음) | Commander |
| 8 | **0점 선수는 저장하지 않음** | Commander |

---

## 4. 데이터 모델

테이블 **2개**. 연결 정보를 미러 밖으로 뺀 것이 핵심이다 — 미러는 크롤마다 갈아엎지만
힘들게 확인한 계정 연결은 살아남아야 한다.

```sql
-- ═══════════════════════════════════════════════
-- org_rankings — 협회 공표 순위표 미러 (현재상태)
--   쓰기: 크롤러(service_role) 부서 단위 delete+insert
-- ═══════════════════════════════════════════════
create table public.org_rankings (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  division_code text not null references public.tennis_divisions(code),
  rank          int  not null check (rank > 0),
  player_name   text not null,
  org_player_id text,           -- 협회 시스템 선수 아이디. null 허용(링크 없는 행 대비)
  club_raw      text,           -- 소속 원문 그대로. 파싱·정규화 안 함
  rank_points   int  not null check (rank_points  >= 0),  -- 화면의 '순위포인트'
  total_points  int  not null check (total_points >= 0),  -- 화면의 '전체포인트'
  source_url    text not null,
  fetched_at    timestamptz not null default now(),
  unique (org_code, division_code, rank),
  unique (org_code, division_code, org_player_id)
);

create index org_rankings_player_name_idx on public.org_rankings (player_name);
create index org_rankings_org_player_idx  on public.org_rankings (org_code, org_player_id);

alter table public.org_rankings enable row level security;

create policy org_rankings_read on public.org_rankings
  for select using (auth.role() = 'authenticated');
create policy org_rankings_admin on public.org_rankings
  for all using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════
-- org_player_links — 협회 선수 ↔ 앱 계정 (크롤과 독립적으로 생존)
-- ═══════════════════════════════════════════════
create table public.org_player_links (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  org_player_id text not null,
  user_id       uuid not null references public.users(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending','confirmed','rejected')),
  claimed_at    timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid references public.users(id),
  unique (org_code, org_player_id, user_id)
);

-- confirmed 는 1:1 강제. pending 은 여럿 허용 — 경합을 관리자가 보고 고른다
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
```

새 테이블은 `anon, authenticated, service_role` DML grant 보충이 필요하다
(클린 재생 시 grant 누락 이력 있음). anon 은 grant 가 있어도 **정책이 없어 0행**이다.

### 4.1 폐기한 컬럼과 이유

| 폐기 | 이유 |
|---|---|
| `season_year` | 협회가 시즌 표기를 안 준다. 우리가 지어내는 값이 된다 |
| `published_on` | 협회 공표일이 없다. 있는 건 우리가 가져온 시각(`fetched_at`)뿐 |
| 단일 `points` | 화면에 포인트 컬럼이 둘이다 |
| `user_id` (미러 안) | 크롤 갱신마다 연결이 날아간다 → 별도 테이블로 분리 |
| 생년월일 매칭 | 협회 데이터에 생년월일이 없다 |

### 4.2 스냅샷 vs 현재상태 — 현재상태 + 원본 아카이브

| | 스냅샷 이력 | **현재상태 + 원본 HTML 보관** |
|---|---|---|
| 쉬운 말 | 크롤할 때마다 사진첩에 한 장씩 | 게시판은 최신 한 장, 원본 서류는 창고에 |
| 지금 요구사항 | 순위 변동 기능 없음 — 과잉 | 딱 맞음 |
| 되돌리기 | — | 원본만 있으면 스냅샷을 **나중에 소급 생성 가능** |
| 실명 보유량 | 크롤마다 수천 행 누적 | 항상 현재 명단만 |

크롤한 HTML 원본을 Supabase Storage 비공개 버킷에 `org/division/날짜.html` 로 보관한다.
스키마 0, 코드 몇 줄.

**이 아카이브는 옵션이 아니라 필수다** — §7 ① 참조.

---

## 5. 매칭 흐름

1. **후보 탐색 (자동)** — `users.name` = `org_rankings.player_name` AND 유저 등록 협회 일치
   AND 유저 `division_codes` 와 부서 일치 → 후보 제시
2. **확정 (원탭)** — "골드부 12위 김평화(어등산) — 본인인가요?" → `pending` 클레임 생성
3. **승인** — 관리자 큐에서 `confirmed` 처리 (기존 검수 큐 패턴 재사용)

유저는 협회 아이디를 몰라도 된다. **행을 고르면 아이디는 우리가 이미 갖고 있다.**

**무언 자동 확정을 하지 않는 이유**: 협회 개인 페이지가 전체 공개라 "본인만 아는 정보"로 검증할
수단이 없고, 오매칭의 결과가 **실명 자동 공개**(결정 3)라 오류 비용이 비대칭적으로 크다.
앱의 김철수를 대회에 나간 적 없는 동명이인 입상자에 붙이는 것이 기본 실패 시나리오다.

**사칭 방어**: `confirmed` 1:1 유니크 + 관리자 승인 + 이의 시 `rejected`. 협회 데이터에 검증
가능한 비밀이 없어 완벽하진 않지만, 경합이 생기면 관리자에게 **보인다**.

---

## 6. 개인정보·법적 방어

- **0점 선수 미저장** (크롤러 필터). 순위는 협회 값을 그대로 쓰므로 0점 구간을 버려도 순위가 안 깨진다
- **개인 이력 팝업 미수집** — 상세 페이지를 아예 fetch 하지 않는다 (선수당 1요청 × 수천 명 방지 겸)
- **anon 읽기 없음** — 협회가 공개한 데이터라도 우리가 비로그인 인터넷에 재공개하면 스크레이핑
  표면과 법적 노출을 새로 만든다. 기존 카탈로그 테이블도 authenticated 전용
- 웹빌드는 랭킹 경로 **검색엔진 색인 차단**

**출시 전 필수 (미완료 시 블로커)**
- [ ] 개인정보처리방침에 **"협회 공표 랭킹 표시"** 항목 추가 (법 §30, 미비 시 과태료 1천만원)
- [ ] **미가입 선수 삭제(이의) 요청 채널** (법 §36 정정·삭제 요구권 — 창구 없으면 대응 자체가 불가)
- [ ] 탈퇴 시 계정 연결 즉시 소멸 (`on delete cascade`). 단 **미러의 해당 행은 남는다** —
      협회가 여전히 공표 중이므로 탈퇴자는 미가입 선수와 같은 취급이 된다. 미러에서까지 지우려면
      삭제(이의) 요청 채널을 타야 한다
- [ ] **협회 동의를 문서로 확보** (구두 동의를 메일 회신 등으로 남김) — 민원 시 유일한 방어 근거

미가입자 실명 전면 노출(결정 4)은 설계 검토 실패 시나리오 ②와 같은 유형의 리스크가 남는다.
결정은 존중하되, 이의 채널이 완충재다.

---

## 7. 나중에 아픈 지점

1. **연말 리셋이 미러를 통째로 지운다.** 호남 3개 협회 모두 연초 포인트 리셋 → 2027년 1월 첫
   크롤이 2026 최종 순위를 영영 덮는다. **12월 마지막 크롤 원본 보관이 유일한 보험**이다
2. **`rank_points` = `total_points` 라고 컬럼을 합치면**, 규정상 둘은 다른 값이라 협회가 화면을
   고치는 날 데이터가 유실된다. 두 컬럼 유지 + 협회 확인 질문을 살려둔다
3. **`org_player_id` 를 안 뽑고 이름으로만 저장하면** 재크롤·동명이인·개명에서 identity 가
   끊긴다. 크롤러 1차 구현부터 `player_rank(...)` 파싱을 필수로 한다

---

## 8. 선행 작업 — 부서 카탈로그 분리

협회 랭킹표는 **국화부와 여자금배부가 별도 랭킹**인데, 우리 카탈로그는 `gj_w_winner`(여자우승자부)
하나에 두 이름을 alias 로 합쳐놨다:

```
('gj_w_winner', 'gj', '여자우승자부', '{우승자부,여자우승자,국화,금배}', ...)
```

`division_code` FK 를 걸려면 국화/금배를 별도 행으로 분리해야 한다.
**부서 카탈로그 스냅샷 다리**(DB ↔ `app/test/fixtures/division_fallback.json` ↔ Dart 폴백)
동기화가 딸려오므로 **별도 선행 PR**로 처리한다.

협회 랭킹표 부서 7개 ↔ 카탈로그 매핑:

| 협회 랭킹표 | 카탈로그 코드 | 상태 |
|---|---|---|
| 골드부 | `gj_m_gold` | OK |
| 남자일반부 | `gj_m_general` | OK |
| 남자신인부 | `gj_m_rookie` | OK |
| 지도자부 | `gj_m_instructor` | OK |
| 여자신인부 | `gj_w_rookie` | OK |
| 국화부 | `gj_w_winner` | **충돌 — 분리 필요** |
| 여자금배부 | `gj_w_winner` | **충돌 — 분리 필요** |

전남(`jn_*`)도 동일 구조인지 크롤 전에 확인한다.

---

## 9. 범위 밖 (이번에 안 만드는 것)

| 항목 | 언제 |
|---|---|
| 배점 계산 로직 (`org_point_rules`) | 협회 제휴 심화 후. `gj-2026.json` 은 이미 정형화돼 있음 |
| 대회별 입상 원천 (`tournament_results`) | 계산 단계. 그때 협회에서 정식으로 받는다 |
| 순위 변동 추이 | 요구사항 없음. 원본 아카이브로 소급 생성 가능 |
| 협회 간 점수 환산 | 공식 환산표 없음 (계획서 확정) |
| KTA·KATO·전북 | 광주·전남 파일럿 성과 확인 후 |

**원천 이력을 지금 안 만드는 근거 정정** — "웹에 있으니 언제든 재수집 가능"은 이 생태계에선
약한 근거다. `gjtennis.net`·`jntennis.co.kr` 두 도메인이 **이미 유실**됐다(리서치 §2.1).
진짜 이유는 이번 범위에 그 데이터가 필요 없고, 필요해지는 시점이 협회 제휴 후라 그때 정식으로
받는 게 맞기 때문이다. 우리가 실제로 가져온 페이지만 Storage 에 보관하면 충분하다.

---

## 10. 협회 확인 항목 (Commander)

1. **`순위포인트`와 `전체포인트`가 왜 같은 값인가** — 규정상 베스트25 vs 베스트15로 달라야 한다
2. 랭킹 갱신 주기 (규정은 "대회 폐막 후 3일 이내")
3. 연초 리셋 시점과 이전 시즌 최종 순위 보관 여부
4. 크롤링 동의 범위 — 요청 빈도, 표시 방식, 출처 표기 문구
