-- 협회 랭킹과 본인 랭킹 의도를 intent_examples 정본에 추가한다.
-- 실제 라우팅은 개인정보가 임베딩 모델로 가기 전에 로컬 룰로 처리하지만,
-- KNN 분류 통계와 seed-intent-examples의 타입 정합성도 같은 의도 목록을 사용한다.

begin;

alter table public.intent_examples
  drop constraint if exists intent_examples_intent_check;

alter table public.intent_examples
  add constraint intent_examples_intent_check
  check (
    intent = any(array[
      'tournament_search',
      'tournament_detail',
      'ranking_lookup',
      'my_ranking',
      'club_search',
      'rule_lookup',
      'venue_search',
      'match_schedule',
      'my_profile',
      'free_chat'
    ])
  );

commit;
