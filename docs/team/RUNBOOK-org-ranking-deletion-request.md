# 런북 — 협회 랭킹 명단 삭제·정정 요청 처리

> 개인정보 보호법 §36(정정·삭제) 대응 창구. `org_rankings`는 협회가 공표한 실명 순위표를
> 그대로 미러링한 테이블이라, 앱 미가입자도 요청할 수 있어야 의미가 있다(2026-08-03 결정,
> 관련: `docs/legal/privacy-policy.html` 2항·6항).

## 접수 창구

- 이메일: `play@jyoungad.kr` (개인정보 보호책임자, 처리방침 7항과 동일)
- 앱 미가입자는 이 이메일이 유일한 접근 경로다. 랭킹 화면 자체에 삭제 요청 UI는 없지만,
  `RankingSourceNotice` 위젯(`app/lib/screens/rankings/rankings_screen.dart`)이 이
  이메일을 상시 노출한다.

### 출시본과 현재 코드의 연락처 차이 (2026-08-08 확인)

현재 코드와 App Store 제품 페이지가 연결하는 개인정보 처리방침은
`play@jyoungad.kr`을 사용한다. 그러나 iOS 출시본 `1.0.0 (5)`는 연락처 수정 전
커밋 `7b1fc40`에서 만든 바이너리라, 협회 랭킹 화면에는 옛 주소
`demian.772@gmail.com`이 표시된다.

다음 버전 출시를 확인하기 전까지는 두 주소로 들어오는 요청을 모두 놓치지 않아야 한다.
옛 주소의 수신·자동전달 유지 여부와 `play@jyoungad.kr`의 실제 수신 여부를 운영자가
확인한다. 근거와 다음 배포 전 확인 사항은
[`RELEASE-STATUS-ios.md`](RELEASE-STATUS-ios.md)에 기록한다.

심사 계정 비밀번호 등 인증정보는 이 런북과 저장소에 기록하지 않는다.

## 처리 절차

1. 요청자 본인 확인: 성명 + 소속(클럽) + 협회(광주/전남) + 부서로 `org_rankings` 행을 특정한다.
   본인 확인이 애매하면(동명이인 등) 회신으로 추가 정보를 요청한다.
2. **억제 목록에 먼저 등록한다.** 이걸 빼먹고 삭제만 하면 다음 크롤이 되살린다.

   **아이디가 있으면 아이디와 성명·소속을 둘 다 넣는다.** 하나만 넣으면 안 된다.
   ```sql
   insert into public.org_ranking_suppressions
     (org_code, org_player_id, player_name, club_raw, note)
   values ('<gj|jn>', '<협회아이디>', '<성명>', '<소속 원문>',
           '2026-__-__ 본인 삭제 요청, 메일 접수');
   ```

   아이디를 못 찾는 행이면 성명 + 소속만 넣는다:
   ```sql
   insert into public.org_ranking_suppressions
     (org_code, player_name, club_raw, note)
   values ('<gj|jn>', '<성명>', '<소속 원문>', '2026-__-__ 본인 삭제 요청, 메일 접수');
   ```

   > **왜 둘 다 넣나.** 파서가 협회 HTML 에서 `org_player_id` 를 **매번 뽑는다는 보장이
   > 없다**(성명 셀의 `player_rank('아이디')` 링크가 없는 행이 있다). 아이디만 등록해 두면,
   > 그 사람이 다음 크롤에 아이디 없이 들어올 때 매칭이 빗나가 **되살아난다.**
   > 두 경로 중 **하나라도 맞으면** 걸러지도록 되어 있다.
   > (`024_ranking_suppression.test.sql` 단언 7 이 이 경우를 지킨다.)
   >
   > `club_raw` 는 협회 표기 **그대로** 넣는다(후행 슬래시 포함, 예: `어등산/`).
   >
   > **`club_raw` 를 비워도 와일드카드가 아니다.** 비우면(`null`) 소속이 비어 있는 행하고만
   > 맞는다 — 소속이 있는 행은 조용히 안 지워진다. 반드시 실제 소속을 넣는다.

3. 이미 저장된 현재 랭킹·랭킹 기록·선수별 대회 이력을 모두 지운다. 선수별 이력은
   `org_player_id`로 연결되므로 아이디가 있는 요청에서 두 테이블을 함께 삭제한다:
   ```sql
   delete from public.org_player_results
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';

   delete from public.org_player_history_fetches
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';

   delete from public.org_rankings
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';
   -- 아이디가 없으면: and player_name = '<성명>' and club_raw = '<소속 원문>'

   delete from public.org_ranking_snapshots
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';
   ```

   아이디가 없는 랭킹 행은 선수 상세 이력의 수집 대상이 아니므로 현재 랭킹과 랭킹
   기록만 성명 + 소속으로 삭제한다.

4. **다음 크롤 이후 재등장하지 않는지 확인한다.** 억제가 걸렸으면 안 돌아온다:
   ```sql
   select count(*) from public.org_rankings
   where org_code = '<gj|jn>' and player_name = '<성명>';

   select count(*) from public.org_player_results
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';

   select count(*) from public.org_player_history_fetches
   where org_code = '<gj|jn>' and org_player_id = '<협회아이디>';
   ```

5. 처리 결과를 요청자에게 회신한다. **원본은 협회에 있다는 점을 함께 안내한다**
   (아래 "남아 있는 한계" 참조).

## ✅ 해결됨 — 삭제가 재크롤로 되살아나지 않는다 (2026-08-04)

이전에는 크롤이 부서 단위로 delete+insert 하기 때문에, 삭제한 행을 다음 크롤이
그대로 되살렸다. 억제 메커니즘이 없어서 "처리했습니다"라고 회신한 다음 날 그 사람이
다시 앱에 떴다.

`org_ranking_suppressions` 테이블과 `replace_org_ranking_division()` 의 필터로 해결했다
(`supabase/migrations/20260804020000_org_ranking_suppressions.sql`).
크롤이 insert 할 때 억제 대상을 걸러내므로, **위 절차 2번을 밟았다면 다시 들어오지 않는다.**

`supabase/tests/database/024_ranking_suppression.test.sql` 이 이걸 지킨다(단언 7개).
필터를 제거하면 4개가 실제로 뒤집히는 것을 변이 주입으로 확인했다.

## ⚠️ 남아 있는 한계 — 원본은 협회에 있다

우리가 지우는 것은 **우리 사본**이다. 협회 홈페이지의 원본 순위표는 그대로 남는다.
서비스에는 그걸 수정할 권한이 없다.

→ 회신할 때 **"원본까지 지우려면 협회에 직접 요청해야 한다"**를 반드시 함께 안내한다.
   이 안내는 랭킹 화면과 처리방침 2항에도 상시 노출된다.

## ⚠️ 남아 있는 한계 — 같은 이름 + 같은 소속

성명 + 소속으로 맞추는 경로는 **이름도 같고 소속도 같은 두 사람을 구분하지 못한다.**
그 조합이 실제로 있으면 억제할 때 둘 다 사라진다.

→ 그 경우는 **`org_player_id` 로만 특정할 수 있다.** 접수 시 협회 페이지에서 아이디를
  확인해 넣고, 성명·소속은 넣지 않는다(아이디만 있는 억제 행으로 등록).
→ 다만 그러면 위의 "아이디가 빠져 들어오는 경우"에 취약해진다. **트레이드오프이므로
  접수할 때 어느 쪽 위험이 큰지 판단한다.** 동명이인이 없다면 둘 다 넣는 쪽이 안전하다.

### 억제 목록을 다룰 때 주의

- 억제 목록 자체가 개인정보다(삭제를 요청한 사람의 성명·소속). RLS 로 관리자만 읽는다.
- 요청자가 나중에 "다시 올려달라"고 하면 억제 행을 지우면 된다. 다음 크롤에 복원된다.

## 확인할 것

- [x] 랭킹 화면(`app/lib/screens/rankings/rankings_screen.dart`)의 `RankingSourceNotice`
      하단에 이 이메일이 표시된다(Task 6, `0463622` 로 반영 완료, 2026-08-03 확인).
