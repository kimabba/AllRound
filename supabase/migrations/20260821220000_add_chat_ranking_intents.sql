-- 협회 랭킹 조회 의도를 intent_examples 정본에 추가한다.
-- 실제 라우팅은 개인정보가 임베딩 모델로 가기 전에 로컬 룰로 처리하지만,
-- KNN 분류 통계와 seed-intent-examples의 타입 정합성도 같은 의도 목록을 사용한다.
--
-- "본인 랭킹"은 여기 포함하지 않는다 — #424가 이미 my_profile 라우팅에
-- my_confirmed_ranking RPC로 통합해뒀다. ranking_lookup은 그와 겹치지 않는
-- "협회 공개 랭킹 조회"(예: "광주 골드부 랭킹")만 다룬다.

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
      'club_search',
      'rule_lookup',
      'venue_search',
      'match_schedule',
      'my_profile',
      'free_chat'
    ])
  );

commit;
