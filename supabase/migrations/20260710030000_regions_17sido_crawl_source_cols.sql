-- 전국 확장 P1(계속): regions 를 17개 시도로 확장 + crawl_sources 에 org/region 코드 컬럼.
-- 비파괴: 기존 8개 권역 코드는 FK 참조(tournaments/user_tennis_orgs)라 삭제하지 않고
--         다중시도 권역만 is_active=false 로 deprecate. 기존 대회의 시도 재분류(backfill)는 후속.

alter table public.regions add column if not exists zone text;                 -- 권역 그룹(표시용)
alter table public.regions add column if not exists is_active boolean not null default true;
alter table public.regions add column if not exists superseded_by text;

insert into public.regions (code, display_name_ko, governing_associations, uses_kato, uses_kata, notes, zone) values
  ('seoul',     '서울', '{"kta"}', true,  true,  null,             'sudogwon'),
  ('gyeonggi',  '경기', '{"kta"}', true,  true,  null,             'sudogwon'),
  ('incheon',   '인천', '{"kta"}', true,  true,  null,             'sudogwon'),
  ('busan',     '부산', '{"kta"}', false, false, null,             'yeongnam'),
  ('ulsan',     '울산', '{"kta"}', false, false, null,             'yeongnam'),
  ('gyeongnam', '경남', '{"kta"}', false, false, null,             'yeongnam'),
  ('daegu',     '대구', '{"kta"}', false, false, null,             'yeongnam'),
  ('gyeongbuk', '경북', '{"kta"}', false, false, null,             'yeongnam'),
  ('daejeon',   '대전', '{"kta"}', false, false, null,             'chungcheong'),
  ('sejong',    '세종', '{"kta"}', false, false, null,             'chungcheong'),
  ('chungbuk',  '충북', '{"kta"}', false, false, null,             'chungcheong'),
  ('chungnam',  '충남', '{"kta"}', false, false, null,             'chungcheong'),
  ('jeonbuk',   '전북', '{"kta"}', false, false, '전북특별자치도.', 'honam')
on conflict (code) do update set zone = excluded.zone;

-- 기존 단일 시도 코드의 zone 보정
update public.regions set zone = 'honam'   where code in ('gwangju','jeonnam');
update public.regions set zone = 'gangwon' where code = 'gangwon';
update public.regions set zone = 'jeju'    where code = 'jeju';

-- 다중 시도 권역 코드 deprecate (삭제 아님)
update public.regions set is_active = false
  where code in ('seoul_metro','busan_ulsan_gn','daegu_gb','chungcheong');

-- crawl_sources: slug 추론 제거를 위한 명시적 org/region 코드
alter table public.crawl_sources add column if not exists org_code text references public.tennis_orgs(code);
alter table public.crawl_sources add column if not exists region_code text references public.regions(code);
update public.crawl_sources set org_code = 'gj', region_code = 'gwangju' where slug = 'tennis-gwangju';
update public.crawl_sources set org_code = 'jn', region_code = 'jeonnam' where slug = 'tennis-jeonnam';
