-- 테니스 경기 핵심 룰북 지식(rule_articles) 보강
--
-- 공식 1차 출처의 최신판인 World Tennis(구 ITF) 2026 Rules of Tennis를
-- 사용자 질문에 답하기 쉬운 한국어로 요약한다. 원문을 길게 복제하지 않고,
-- 대회별로 달라질 수 있는 대체 스코어링 방식은 사전 공지가 필요함을 구분한다.
--
-- 같은 sport/title 행이 이미 있으면 내용을 최신 요약으로 맞추고, 없으면 삽입한다.
-- 이 때문에 마이그레이션 SQL을 재실행해도 같은 title의 행이 늘어나지 않는다.
-- 신규·변경 행의 embedding은 NULL로 두어 기존 embed-pending 워커가 생성하게 한다.

begin;

with seed(sport, category, title, body, order_idx) as (
  values
    (
      'tennis'::public.sport,
      '스코어',
      '테니스 게임 스코어와 듀스는 어떻게 계산하나요?',
      $body$일반 게임에서는 서버의 점수를 먼저 부르며 0(러브) → 15 → 30 → 40 순서로 올라갑니다. 한쪽이 첫 세 포인트를 연속으로 따면 40-0이고, 다음 포인트까지 따면 게임을 이깁니다.

양쪽이 세 포인트씩 따면 40-40이 아니라 "듀스"라고 부릅니다. 듀스 뒤 한 포인트를 이기면 어드밴티지, 이어지는 다음 포인트도 이기면 게임 승리입니다. 어드밴티지 선수가 다음 포인트를 잃으면 다시 듀스로 돌아갑니다. 따라서 듀스 뒤에는 연속 두 포인트가 필요합니다.

이 설명은 표준 게임 기준입니다. 노애드처럼 승인된 대체 스코어 방식은 대회가 미리 공지한 경우에만 적용하므로 참가 대회의 요강도 함께 확인해야 합니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 5-7 및 Appendix VI
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      100
    ),
    (
      'tennis'::public.sport,
      '스코어',
      '세트와 매치는 몇 게임, 몇 세트를 이겨야 하나요?',
      $body$세트 방식은 경기 전에 정합니다. 타이브레이크 세트에서는 먼저 6게임을 따고 상대보다 2게임 이상 앞서면 세트를 이깁니다. 6-6이 되면 타이브레이크를 합니다. 어드밴티지 세트도 6게임과 2게임 차가 필요하지만 6-6 타이브레이크 없이 두 게임 차가 날 때까지 계속합니다.

매치는 보통 3세트 중 2세트를 먼저 따는 방식 또는 5세트 중 3세트를 먼저 따는 방식입니다. 결정 세트를 10포인트 매치 타이브레이크로 대신하는 등 승인된 대체 방식도 있으나 자동 적용되는 공통 규칙은 아닙니다. 실제 경기의 세트 방식과 결정 세트 운영은 대회가 사전에 공지한 요강을 확인해야 합니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 6-7 및 Appendix VI
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      101
    ),
    (
      'tennis'::public.sport,
      '타이브레이크',
      '7포인트 타이브레이크의 점수와 서브 순서는 어떻게 되나요?',
      $body$일반적인 세트 타이브레이크는 0, 1, 2, 3처럼 포인트를 셉니다. 먼저 7포인트에 도달하면서 상대보다 2포인트 이상 앞선 선수 또는 팀이 게임과 세트를 이깁니다. 6-6이면 끝나지 않고 8-6, 9-7처럼 두 포인트 차가 날 때까지 계속합니다.

타이브레이크를 시작할 차례인 선수가 첫 1포인트를 서브합니다. 그다음은 상대가 2포인트를 연속 서브하고, 이후 양쪽이 2포인트씩 번갈아 서브합니다. 서브 위치는 첫 포인트를 오른쪽에서 시작해 포인트마다 오른쪽과 왼쪽을 교대합니다. 복식은 그 세트에서 사용하던 팀 내 서브 순서를 그대로 이어갑니다.

타이브레이크에서 첫 서브를 한 선수 또는 팀은 다음 세트 첫 게임에서 리시브합니다. 10포인트 매치 타이브레이크는 경기 전에 채택된 경우 결정 세트를 대신하며, 10점과 2점 차가 필요합니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rule 5 및 Appendix VI
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      102
    ),
    (
      'tennis'::public.sport,
      '서브',
      '서브 차례와 서브 위치의 기본 규칙은 무엇인가요?',
      $body$표준 게임이 끝날 때마다 서버와 리시버가 바뀝니다. 한 게임 안에서는 같은 선수가 계속 서브하고, 매 포인트마다 오른쪽과 왼쪽을 번갈아 섭니다. 각 게임의 첫 포인트는 오른쪽에서 시작합니다. 타이브레이크도 첫 포인트는 오른쪽이며 이후 포인트마다 좌우를 교대합니다.

서버는 베이스라인 뒤에서 센터마크와 해당 사이드라인의 가상 연장선 사이에 두 발을 두고 동작을 시작해야 합니다. 공은 네트를 넘어 대각선 반대편의 올바른 서비스 코트에 첫 바운드해야 합니다. 베이스라인이나 코트를 밟거나, 사이드라인 바깥 또는 센터마크 연장선을 침범하면 풋폴트입니다.

첫 서브가 폴트면 지체 없이 같은 쪽에서 두 번째 서브를 합니다. 두 번째 서브도 폴트면 그 포인트를 잃습니다. 다만 잘못된 쪽에서 서브한 사실을 발견했다면 즉시 올바른 위치로 고치고, 발견 전 포인트는 유효합니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 14, 16-20 및 27
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      103
    ),
    (
      'tennis'::public.sport,
      '렛',
      '서브 렛과 일반 렛은 언제 다시 하나요?',
      $body$서브가 네트·스트랩·밴드를 건드린 뒤에도 올바른 서비스 코트에 들어가면 서브 렛입니다. 네트를 건드린 공이 바운드 전에 리시버나 리시버 파트너 또는 그 착용물에 닿은 경우도 서브 렛입니다. 리시버가 준비되지 않았는데 서브한 경우에도 렛이 될 수 있습니다.

서브 렛이 선언되면 그 서브만 다시 합니다. 첫 서브 폴트 뒤 두 번째 서브가 렛이면 첫 폴트가 사라지는 것이 아니라 두 번째 서브를 다시 합니다. 일반 렛은 원칙적으로 포인트 전체를 다시 하지만, 두 번째 서브에서 발생한 서브 렛은 위와 같이 해당 서브만 반복합니다.

공식 규칙에는 승인된 노렛 방식도 있습니다. 네트에 닿은 서브를 그대로 인플레이로 보는 노렛은 대회가 미리 채택한 경우에만 적용하므로 요강을 확인해야 합니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 21-23 및 Appendix VI
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      104
    ),
    (
      'tennis'::public.sport,
      '코트 교대',
      '코트는 언제 바꾸나요?',
      $body$각 세트의 첫 번째, 세 번째, 그리고 그 뒤 모든 홀수 게임이 끝날 때 코트를 바꿉니다. 세트가 끝났을 때도 코트를 바꾸지만, 그 세트의 총 게임 수가 짝수라면 즉시 바꾸지 않고 다음 세트 첫 게임이 끝난 뒤 바꿉니다.

표준 타이브레이크에서는 합계 6포인트마다 코트를 바꿉니다. 예를 들어 3-3, 6-6처럼 여섯 포인트 단위가 끝난 시점입니다. 경기 운영자가 Appendix VI의 승인된 대체 코트 교대 절차를 사전에 채택했다면 그 공지된 방식을 따릅니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rule 10 및 Appendix VI
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      105
    ),
    (
      'tennis'::public.sport,
      '인·아웃',
      '라인에 닿으면 인인가요? 인·아웃은 어떻게 판단하나요?',
      $body$공이 라인에 조금이라도 닿으면 그 라인이 둘러싼 코트에 닿은 것으로 보므로 인입니다. 랠리 중에는 공이 올바른 코트에 첫 바운드하기 전에 영구 시설물에 닿으면 그 공을 친 선수가 포인트를 잃습니다. 올바른 코트에 먼저 바운드한 뒤 영구 시설물에 닿으면 그 공을 친 선수가 포인트를 얻습니다.

상대 코트 안에 첫 바운드한 공은 네트·스트랩·밴드·네트 포스트 등을 건드리고 넘어갔더라도 유효 리턴이 될 수 있습니다. 공이 네트를 넘어 다시 자기 쪽으로 되돌아오는 경우에는 네트 너머로 라켓을 뻗어 칠 수 있지만, 상대 코트나 네트에 몸이나 라켓이 닿아서는 안 됩니다.

공이 두 번 바운드하기 전에 되받지 못하거나, 리턴한 공의 첫 바운드가 올바른 코트 밖이면 그 포인트를 잃습니다. 복식에서는 싱글 사이드라인이 아니라 더 바깥쪽 복식 사이드라인이 인·아웃 경계입니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 1, 12-13 및 24-25
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      106
    ),
    (
      'tennis'::public.sport,
      '복식',
      '복식의 서브와 리시브 순서는 어떻게 정하나요?',
      $body$복식에서는 세트 첫 게임을 맡은 팀이 두 선수 중 첫 서버를 정합니다. 상대 팀도 두 번째 게임의 첫 서버를 정합니다. 첫 팀의 파트너가 세 번째 게임, 상대 팀의 파트너가 네 번째 게임을 서브하며 이 네 게임 순환을 세트 끝까지 반복합니다.

리시브 팀은 그 세트에서 처음 리시브하는 게임을 시작하기 전에 첫 포인트의 리시버를 정합니다. 파트너가 두 번째 포인트를 받고, 게임이 끝날 때까지 두 사람이 번갈아 리시브합니다. 같은 세트에서 그 팀이 리시브하는 다음 게임들도 이 순서를 유지합니다. 서브 리턴 뒤 랠리에서는 어느 파트너가 공을 쳐도 됩니다.

새 세트가 시작되면 팀은 서브와 리시브의 팀 내 순서를 다시 정할 수 있습니다. 순서 오류를 발견했을 때는 공식 오류 수정 규칙에 따라 이미 끝난 포인트는 유지하고, 발견 시점과 종류에 맞춰 순서를 바로잡습니다.

공식 출처: World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English), Rules 14-15 및 27
URL: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
      107
    )
),
updated as (
  update public.rule_articles as r
  set
    category = s.category,
    body = s.body,
    order_idx = s.order_idx,
    embedding = null,
    embedding_updated_at = null
  from seed as s
  where r.sport = s.sport
    and r.title = s.title
  returning r.sport, r.title
)
insert into public.rule_articles (
  sport,
  category,
  title,
  body,
  order_idx,
  published,
  embedding,
  embedding_updated_at
)
select
  s.sport,
  s.category,
  s.title,
  s.body,
  s.order_idx,
  false, -- Commander 검수 후 공개(2026-08-19 unpublish_unreviewed_2026_tennis_rules 참고)
  null::vector(768),
  null::timestamptz
from seed as s
where not exists (
  select 1
  from updated as u
  where u.sport = s.sport
    and u.title = s.title
)
and not exists (
  select 1
  from public.rule_articles as r
  where r.sport = s.sport
    and r.title = s.title
);

commit;
