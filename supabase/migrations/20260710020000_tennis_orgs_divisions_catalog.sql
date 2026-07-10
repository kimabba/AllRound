-- 전국 확장 P1: 협회·부서를 enum/코드하드코딩 → 테이블(디렉터리)로.
-- 비파괴: 기존 tennis_org enum / TENNIS_DIVISIONS(enums.ts) 와 병존한다.
-- 이후 단계에서 매칭/크롤러가 이 테이블을 참조하도록 전환.

-- =========================================================
-- 1. tennis_orgs — 협회 디렉터리 (enum tennis_org 테이블화)
-- =========================================================
create table if not exists public.tennis_orgs (
  code text primary key,
  name_ko text not null,
  short_label text,
  org_type text not null check (org_type in ('national','sido','sigungu','club')),
  region_code text references public.regions(code),
  division_scheme text,                         -- 부서 체계 그룹 (예: 'sido_std')
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.tennis_orgs enable row level security;
create policy tennis_orgs_read on public.tennis_orgs
  for select using (auth.role() = 'authenticated');
create policy tennis_orgs_admin on public.tennis_orgs
  for all using (public.is_admin()) with check (public.is_admin());

insert into public.tennis_orgs (code, name_ko, short_label, org_type, region_code, division_scheme, is_active) values
  ('kta',   '대한테니스협회',              'KTA',   'national', null,      'kta',        true),
  ('kato',  '한국테니스발전협의회',         'KATO',  'national', null,      'kato',       true),
  ('kata',  '한국동호인테니스협회',         'KATA',  'national', null,      'kata',       true),
  ('ktfs',  '국민생활체육 전국테니스연합회', 'KTFS',  'national', null,      'ktfs',       false), -- 2016 KTA 흡수(소멸), 기존데이터 위해 존치
  ('kstf',  '한국시니어테니스연맹',         'KSTF',  'national', null,      'kstf_senior',true),
  ('kssta', '한국슈퍼시니어테니스협회',     'KSSTA', 'national', null,      'kstf_senior',true),
  ('kasta', '단식테니스(단테매)',          'KASTA', 'national', null,      'kasta',      true),
  ('gj',    '광주광역시테니스협회',         'GJTA',  'sido',     'gwangju', 'sido_std',   true),
  ('jn',    '전라남도테니스협회',           'JNTA',  'sido',     'jeonnam', 'sido_std',   true),
  ('local', '시·군/클럽 자체',             null,    'club',     null,      'local',      true)
on conflict (code) do update set
  name_ko = excluded.name_ko,
  short_label = excluded.short_label,
  org_type = excluded.org_type,
  region_code = excluded.region_code,
  division_scheme = excluded.division_scheme,
  is_active = excluded.is_active;

-- =========================================================
-- 2. tennis_divisions — 부서 사전 (division dictionary)
--    범용 매칭축: skill_tier × gender × age × event_type (+ champion_only 자격플래그)
--    equiv_group: 협회 경계 넘는 동치 그룹. gj/jn 동일 suffix → 같은 그룹
--    → 이후 expand_gj_jn_codes() 를 이 데이터로 대체.
-- =========================================================
create table if not exists public.tennis_divisions (
  code text primary key,
  org_code text not null references public.tennis_orgs(code),
  label_ko text not null,
  synonyms text[] not null default '{}',
  skill_tier text check (skill_tier in ('rookie','intermediate','advanced','open')),
  gender text not null default 'all' check (gender in ('male','female','mixed','all')),
  age_min int,
  champion_only boolean not null default false,
  event_type text not null default 'doubles'
    check (event_type in ('doubles','singles','mixed','couple','team')),
  equiv_group text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists tennis_divisions_org_idx on public.tennis_divisions(org_code);
create index if not exists tennis_divisions_equiv_idx on public.tennis_divisions(equiv_group);

alter table public.tennis_divisions enable row level security;
create policy tennis_divisions_read on public.tennis_divisions
  for select using (auth.role() = 'authenticated');
create policy tennis_divisions_admin on public.tennis_divisions
  for all using (public.is_admin()) with check (public.is_admin());

-- gj/jn (동일 체계 → equiv_group 'sido_std:<suffix>' 로 광주↔전남 자연 동치)
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, age_min, champion_only, event_type, equiv_group) values
  ('gj_m_open',      'gj', '오픈부',     '{오픈부,남자오픈,오픈}',           'open',        'male',   null, false, 'doubles', 'sido_std:m_open'),
  ('gj_m_gold',      'gj', '골드부',     '{골드부,골드}',                   'advanced',    'male',   null, false, 'doubles', 'sido_std:m_gold'),
  ('gj_m_general',   'gj', '일반부',     '{남자일반부,일반부,남자일반}',      'intermediate','male',   null, false, 'doubles', 'sido_std:m_general'),
  ('gj_m_instructor','gj', '지도자부',   '{지도자부,지도자}',                'advanced',    'male',   null, false, 'doubles', 'sido_std:m_instructor'),
  ('gj_m_masters',   'gj', '마스터즈부', '{마스터즈부,마스터즈}',            'open',        'male',   null, false, 'doubles', 'sido_std:m_masters'),
  ('gj_m_rookie',    'gj', '신인부',     '{남자신인부,신인부,신인}',         'rookie',      'male',   null, false, 'doubles', 'sido_std:m_rookie'),
  ('gj_m_veteran',   'gj', '베테랑부',   '{베테랑부,베테랑}',                'intermediate','male',   null, false, 'doubles', 'sido_std:m_veteran'),
  ('gj_m_beginner',  'gj', '초급자부',   '{초급자부,비입상자부,초급자}',      'rookie',      'male',   null, false, 'doubles', 'sido_std:m_beginner'),
  ('gj_w_open',      'gj', '여자오픈부', '{여자오픈부,여자오픈}',            'open',        'female', null, false, 'doubles', 'sido_std:w_open'),
  ('gj_w_winner',    'gj', '여자우승자부','{우승자부,여자우승자,국화,금배}',  'advanced',    'female', null, true,  'doubles', 'sido_std:w_winner'),
  ('gj_w_rookie',    'gj', '여자신인부', '{여자신인부,여자신인,개나리}',      'rookie',      'female', null, false, 'doubles', 'sido_std:w_rookie'),
  ('gj_couple',      'gj', '부부부',     '{부부부,부부}',                   null,          'mixed',  null, false, 'couple',  'sido_std:couple'),
  ('gj_cross',       'gj', '크로스대회', '{크로스}',                        null,          'mixed',  null, false, 'mixed',   'sido_std:cross'),
  ('jn_m_open',      'jn', '오픈부',     '{오픈부,남자오픈,오픈}',           'open',        'male',   null, false, 'doubles', 'sido_std:m_open'),
  ('jn_m_gold',      'jn', '골드부',     '{골드부,골드}',                   'advanced',    'male',   null, false, 'doubles', 'sido_std:m_gold'),
  ('jn_m_general',   'jn', '일반부',     '{남자일반부,일반부,남자일반}',      'intermediate','male',   null, false, 'doubles', 'sido_std:m_general'),
  ('jn_m_instructor','jn', '지도자부',   '{지도자부,지도자}',                'advanced',    'male',   null, false, 'doubles', 'sido_std:m_instructor'),
  ('jn_m_masters',   'jn', '마스터즈부', '{마스터즈부,마스터즈}',            'open',        'male',   null, false, 'doubles', 'sido_std:m_masters'),
  ('jn_m_rookie',    'jn', '신인부',     '{남자신인부,신인부,신인}',         'rookie',      'male',   null, false, 'doubles', 'sido_std:m_rookie'),
  ('jn_m_veteran',   'jn', '베테랑부',   '{베테랑부,베테랑}',                'intermediate','male',   null, false, 'doubles', 'sido_std:m_veteran'),
  ('jn_m_beginner',  'jn', '초급자부',   '{초급자부,비입상자부,초급자}',      'rookie',      'male',   null, false, 'doubles', 'sido_std:m_beginner'),
  ('jn_w_open',      'jn', '여자오픈부', '{여자오픈부,여자오픈}',            'open',        'female', null, false, 'doubles', 'sido_std:w_open'),
  ('jn_w_winner',    'jn', '여자우승자부','{우승자부,여자우승자,국화,금배}',  'advanced',    'female', null, true,  'doubles', 'sido_std:w_winner'),
  ('jn_w_rookie',    'jn', '여자신인부', '{여자신인부,여자신인,개나리}',      'rookie',      'female', null, false, 'doubles', 'sido_std:w_rookie'),
  ('jn_couple',      'jn', '부부부',     '{부부부,부부}',                   null,          'mixed',  null, false, 'couple',  'sido_std:couple'),
  ('jn_cross',       'jn', '크로스대회', '{크로스}',                        null,          'mixed',  null, false, 'mixed',   'sido_std:cross'),
  -- KTA
  ('kta_m_open',     'kta', '남자오픈',   '{남자오픈,오픈}',   'open',        'male',   null, false, 'doubles', 'kta:m_open'),
  ('kta_w_open',     'kta', '여자오픈',   '{여자오픈}',        'open',        'female', null, false, 'doubles', 'kta:w_open'),
  ('kta_mixed',      'kta', '혼합복식',   '{혼합복식,혼복}',    null,          'mixed',  null, false, 'mixed',   'kta:mixed'),
  ('kta_senior_60',  'kta', '시니어 60+', '{시니어60,60대}',   null,          'all',    60,   false, 'doubles', 'senior:60'),
  ('kta_senior_65',  'kta', '시니어 65+', '{시니어65,65대}',   null,          'all',    65,   false, 'doubles', 'senior:65'),
  -- KATA (부수제 1부=최상 → 5부=하위)
  ('kata_1', 'kata', '1부', '{1부}', 'open',         'male',   null, false, 'doubles', null),
  ('kata_2', 'kata', '2부', '{2부}', 'advanced',     'male',   null, false, 'doubles', null),
  ('kata_3', 'kata', '3부', '{3부}', 'intermediate', 'male',   null, false, 'doubles', null),
  ('kata_4', 'kata', '4부', '{4부}', 'rookie',       'male',   null, false, 'doubles', null),
  ('kata_5', 'kata', '5부', '{5부}', 'rookie',       'male',   null, false, 'doubles', null),
  ('kata_w', 'kata', '여자부', '{여자부}', null,      'female', null, false, 'doubles', null),
  -- KTFS
  ('ktfs_open',     'ktfs', '오픈', '{오픈}', 'open',         'all', null, false, 'doubles', null),
  ('ktfs_general',  'ktfs', '일반', '{일반}', 'intermediate', 'all', null, false, 'doubles', null),
  ('ktfs_beginner', 'ktfs', '초급', '{초급}', 'rookie',       'all', null, false, 'doubles', null),
  ('ktfs_w',        'ktfs', '여자부', '{여자부}', null,        'female', null, false, 'doubles', null),
  -- KSTF (시니어 연령축)
  ('kstf_60', 'kstf', '60+부', '{60부,60대}', null, 'all', 60, false, 'doubles', 'senior:60'),
  ('kstf_65', 'kstf', '65+부', '{65부,65대}', null, 'all', 65, false, 'doubles', 'senior:65'),
  ('kstf_70', 'kstf', '70+부', '{70부,70대}', null, 'all', 70, false, 'doubles', 'senior:70'),
  -- local
  ('local_open',    'local', '자체 오픈', '{오픈}', 'open',         'all', null, false, 'doubles', null),
  ('local_general', 'local', '자체 일반', '{일반}', 'intermediate', 'all', null, false, 'doubles', null),
  ('local_rookie',  'local', '자체 신인', '{신인}', 'rookie',       'all', null, false, 'doubles', null),
  ('local_w',       'local', '자체 여자부', '{여자부}', null,        'female', null, false, 'doubles', null)
on conflict (code) do update set
  org_code = excluded.org_code,
  label_ko = excluded.label_ko,
  synonyms = excluded.synonyms,
  skill_tier = excluded.skill_tier,
  gender = excluded.gender,
  age_min = excluded.age_min,
  champion_only = excluded.champion_only,
  event_type = excluded.event_type,
  equiv_group = excluded.equiv_group;
