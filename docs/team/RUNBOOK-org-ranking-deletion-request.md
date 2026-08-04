# 런북 — 협회 랭킹 명단 삭제·정정 요청 처리

> 개인정보 보호법 §36(정정·삭제) 대응 창구. `org_rankings`는 협회가 공표한 실명 순위표를
> 그대로 미러링한 테이블이라, 앱 미가입자도 요청할 수 있어야 의미가 있다(2026-08-03 결정,
> 관련: `docs/legal/privacy-policy.html` 2항·6항).

## 접수 창구

- 이메일: `ssfak@jyoungad.kr` (개인정보 보호책임자, 처리방침 7항과 동일)
- 앱 미가입자는 이 이메일이 유일한 접근 경로다. 랭킹 화면 자체에 삭제 요청 UI는 없지만,
  `RankingSourceNotice` 위젯(`app/lib/screens/rankings/rankings_screen.dart`)이 이
  이메일을 상시 노출한다.

### ⚠️ 옛 주소(`demian.772@gmail.com`)를 아직 닫으면 안 된다 (2026-08-04)

연락처를 `ssfak@jyoungad.kr` 로 바꿨지만, **옛 주소로 요청이 계속 들어온다.**

1. **출시된 iOS 빌드(1.0.0+5)는 여전히 옛 주소를 표시한다.** 앱 코드 변경은 다음 빌드부터
   적용되고, 사용자가 업데이트해야 반영된다. 강제 업데이트 장치도 없다.
2. 공개된 처리방침·약관을 이미 본 사람은 옛 주소를 알고 있다.

→ **옛 주소를 수신 가능한 상태로 유지**하고, 가능하면 새 주소로 **자동 전달**을 걸어 둔다.
→ 출시본이 새 빌드로 충분히 교체된 뒤에 닫는 것을 검토한다. 그 전에 닫으면
   개인정보 삭제 요청이 **도달하지 못한 채 사라진다** — 법 §36 대응 창구가 끊기는 것이다.

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
협회가 다음 날에도 같은 선수를 계속 공표하면, 하루 1회 도는 크롤(매일 KST 06:00경 —
전체 크롤 소스와 함께 단일 스케줄러 `crawl-dispatch` cron, UTC 21:00 이 실행한다.
`crawl_sources.schedule_cron` 값은 현재 dispatcher 가 평가하지 않는 참고용 값이라
실제 실행 시각이 아니다)이 **삭제한 행을 그대로 되살린다.** 억제(suppress)·블록리스트
메커니즘은 현재 코드베이스에 없다(2026-08-03 확인).

**임시 대응**: 요청이 들어오면 삭제 후, 다음 크롤 이후 행이 재등장하는지 수동으로
확인한다(`select * from org_rankings where player_name = '...'`). 재등장하면 다시 삭제하고
요청자에게 "협회가 원본에서 계속 공표 중이라 저희 쪽에서 지워도 다시 나타날 수 있다"고
안내하며, 근본 해결을 원하면 협회 원본 게시물에도 정정을 요청하도록 안내한다.

**구조적 해결(백로그, 미구현)**: `org_player_id`(또는 성명+소속) 기준 억제 테이블을 만들어
크롤 RPC가 insert 시 걸러내게 하는 것이 정답이다. 스키마 변경이므로 구현 전
`backend-architect` 소환 대상이다. 삭제 요청이 실제로 들어오기 전까지는 만들지 않는다
(YAGNI) — 다만 §36 실효성 문제이므로 **첫 요청이 들어오면 바로 만들어야 한다.**

## 확인할 것

- [x] 랭킹 화면(`app/lib/screens/rankings/rankings_screen.dart`)의 `RankingSourceNotice`
      하단에 이 이메일이 표시된다(Task 6, `0463622` 로 반영 완료, 2026-08-03 확인).
