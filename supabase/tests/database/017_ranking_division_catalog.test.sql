begin;

create extension if not exists pgtap with schema extensions;
set search_path to public, extensions;

select plan(6);

-- 협회 랭킹표의 7개 부서가 모두 카탈로그에 있어야 한다 (광주)
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_m_gold','gj_m_general','gj_m_rookie','gj_m_instructor',
                  'gj_w_rookie','gj_w_gukhwa','gj_w_geumbae')),
  7, '광주 랭킹 부서 7개가 카탈로그에 존재');

select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('jn_m_gold','jn_m_general','jn_m_rookie','jn_m_instructor',
                  'jn_w_rookie','jn_w_gukhwa','jn_w_geumbae')),
  7, '전남 랭킹 부서 7개가 카탈로그에 존재');

-- 새 부서는 랭킹 등급이어야 한다
select is(
  (select bool_and(is_ranking_grade) from public.tennis_divisions
   where code in ('gj_w_gukhwa','gj_w_geumbae','jn_w_gukhwa','jn_w_geumbae')),
  true, '국화·금배는 is_ranking_grade = true');

-- 기존 여자우승자부는 살아 있어야 한다
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_w_winner','jn_w_winner')),
  2, '여자우승자부는 삭제되지 않았다');

-- alias 충돌 제거: '국화'/'금배' 가 winner 의 synonyms 에 남아 있으면 안 된다
select is(
  (select count(*)::int from public.tennis_divisions
   where code in ('gj_w_winner','jn_w_winner')
     and synonyms && array['국화','금배']),
  0, 'winner 의 synonyms 에서 국화·금배 제거됨');

-- 새 부서에 synonyms 가 붙어 있어야 요강 파서가 매칭한다
select is(
  (select bool_and(array_length(synonyms, 1) > 0) from public.tennis_divisions
   where code in ('gj_w_gukhwa','gj_w_geumbae','jn_w_gukhwa','jn_w_geumbae')),
  true, '새 부서에 synonyms 존재');

select * from finish();
rollback;
