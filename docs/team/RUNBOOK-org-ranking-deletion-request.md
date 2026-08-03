# 런북 — 협회 랭킹 명단 삭제·정정 요청 처리

> 개인정보 보호법 §36(정정·삭제) 대응 창구. `org_rankings`는 협회가 공표한 실명 순위표를
> 그대로 미러링한 테이블이라, 앱 미가입자도 요청할 수 있어야 의미가 있다(2026-08-03 결정,
> 관련: `docs/legal/privacy-policy.html` 2항·6항, `docs/legal/org-ranking-crawl-consent.md`).

## 접수 창구

- 이메일: `demian.772@gmail.com` (개인정보 보호책임자, 처리방침 7항과 동일)
- 앱 미가입자는 이 이메일이 유일한 접근 경로다. 랭킹 화면 자체에 삭제 요청 UI는 없다
  (Task 6 `RankingSourceNotice` 위젯 — 별도 확인 필요, 아래 "확인할 것" 참고).

## 처리 절차

1. 요청자 본인 확인: 성명 + 소속(클럽) + 협회(광주/전남) + 부서로 `org_rankings` 행을 특정한다.
   본인 확인이 애매하면(동명이인 등) 회신으로 추가 정보를 요청한다.
2. 해당 행 삭제:
   ```sql
   delete from public.org_rankings
   where org_code = '<gj|jn>' and division_code = '<부서코드>' and player_name = '<성명>'
     and club_raw = '<소속 원문>';  -- 동명이인 방지, org_player_id 가 있으면 그걸로 특정
   ```
3. 처리 결과를 요청자에게 회신한다.

## ⚠️ 알려진 한계 — 삭제가 영구적이지 않다

`org_rankings`는 크롤마다 `replace_org_ranking_division()` RPC가 **부서 단위로
delete+insert**한다(`supabase/migrations/20260803030000_ranking_crawl_sources.sql`).
협회가 다음 날에도 같은 선수를 계속 공표하면, 하루 1회 도는 크롤(광주 22:10, 전남 22:20 KST)이
**삭제한 행을 그대로 되살린다.** 억제(suppress)·블록리스트 메커니즘은 현재 코드베이스에
없다(2026-08-03 확인).

**임시 대응**: 요청이 들어오면 삭제 후, 다음 크롤 이후 행이 재등장하는지 수동으로
확인한다(`select * from org_rankings where player_name = '...'`). 재등장하면 다시 삭제하고
요청자에게 "협회가 원본에서 계속 공표 중이라 저희 쪽에서 지워도 다시 나타날 수 있다"고
안내하며, 근본 해결을 원하면 협회 원본 게시물에도 정정을 요청하도록 안내한다.

**구조적 해결(백로그, 미구현)**: `org_player_id`(또는 성명+소속) 기준 억제 테이블을 만들어
크롤 RPC가 insert 시 걸러내게 하는 것이 정답이다. 스키마 변경이므로 구현 전
`backend-architect` 소환 대상이다. 삭제 요청이 실제로 들어오기 전까지는 만들지 않는다
(YAGNI) — 다만 §36 실효성 문제이므로 **첫 요청이 들어오면 바로 만들어야 한다.**

## 확인할 것

- [ ] 랭킹 화면(`app/lib/screens/rankings/rankings_screen.dart`, `feature/JY-ranking-screen`
      브랜치)의 `RankingSourceNotice` 하단에 이 이메일이 표시되는지 — 이 문서 작성 시점
      (2026-08-03) 기준 표시되지 않는다. Task 6 담당 또는 후속 작업에서 추가 확인 필요.
