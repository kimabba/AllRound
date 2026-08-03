# 협회 랭킹 크롤 동의 기록

> 이 저장소는 **PUBLIC**이다. 협회 담당자 연락처·서명 이미지가 포함된 원본 동의 자료는
> 여기 커밋하지 않는다. 아래는 동의 **사실·일자·범위·담당 부서 요약**만 남기고, 원본은
> 별도 보관처(Drive 등)에 두고 링크만 적는다.
>
> 이 문서는 미가입 선수 실명을 앱에 표시하는 결정(2026-08-03, `org_rankings` 미러링)을
> 지탱하는 유일한 방어 근거다(설계 스펙 §6). `TODO(Commander):` 표시된 항목은 실제
> 동의 내용으로 채워져야 완결된다 — 채워지지 않으면 Task 6(랭킹 화면) 공개를 보류한다.

## 동의 대상 기관

- 광주광역시테니스협회
- 전라남도테니스협회

## 동의 사실

- 동의 확보 방식: TODO(Commander): 구두 / 메일 회신 / 공문 등 실제 방식
- 동의 일자: TODO(Commander)
- 동의한 담당 부서·담당자: TODO(Commander): 부서명만 (개인 연락처는 원본 보관처에만)
- 원본 보관 위치(링크만): TODO(Commander): Drive 등 링크

## 동의 범위 확인 항목

아래 4가지가 실제 동의 내용에 포함되는지 확인하고 각 항목에 결과를 채운다.

- [ ] 크롤 대상: 부서별 랭킹표 (현재 구현 = 부서 7개, `gnuboard_ranking.ts`
      `MEMBER_KIND_SUFFIX`와 `docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md`
      기준) — TODO(Commander): 동의 범위와 일치 확인
- [ ] 요청 빈도: 하루 1회 (`crawl_sources.schedule_cron`, 광주 22:10 / 전남 22:20 KST)
      — TODO(Commander): 동의 범위와 일치 확인
- [ ] 앱 내 표시 방식: 순위·성명·소속·전체포인트를 로그인 사용자에게만 표시
      (`org_rankings_read` RLS, `auth.role() = 'authenticated'`) — TODO(Commander): 동의
      범위와 일치 확인
- [ ] 출처 표기 문구: 랭킹 화면에 "{협회명} 공표 데이터 · 참고용이며 협회 공표가
      우선합니다" 상시 노출 (`RankingSourceNotice`, `app/lib/screens/rankings/rankings_screen.dart`)
      — TODO(Commander): 협회가 요구하는 정확한 출처 표기 문구가 따로 있는지 확인

## 삭제·정정 요청과의 관계

명단에 오른 개인(가입자·미가입자 불문)의 삭제 요청 처리 절차는
`docs/team/RUNBOOK-org-ranking-deletion-request.md` 참고. 다만 이 절차만으로는
협회가 원본에서 계속 공표하는 한 우리 미러에서도 재등장할 수 있다(크롤이 매일
같은 데이터를 다시 가져오므로) — 근본적으로는 이 동의 범위 안에서 협회와 함께
처리해야 하는 사안이다.
