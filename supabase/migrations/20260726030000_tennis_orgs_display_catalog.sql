-- JY-135: 협회 표시 정본을 Dart 하드코딩에서 DB 로 옮긴다.
--
-- 지금까지 협회 목록·라벨은 app/lib/utils/grade_labels.dart 의 const 3종
-- (tennisOrgs·tennisOrgLabels·tennisOrgShortLabels)이 정본이었다. 협회를 하나
-- 추가하려면 Dart·TS·데이터를 각각 고쳐야 했고, 실제로 tennis_orgs 테이블의
-- short_label 은 앱과 어긋나 있었다(gj=GJTA vs 앱 "광주협회", local=null).
--
-- 이 마이그레이션 뒤에는 tennis_orgs 가 정본이다. 협회 추가 = 행 INSERT 하나.

alter table public.tennis_orgs
  add column if not exists label_ko text,
  -- 표시 순서 정본. not null default 1000 이라 값을 안 정해도 INSERT 되고,
  -- 지정하지 않은 행은 끝으로 모인다(정렬은 sort_order, name_ko, code).
  add column if not exists sort_order integer not null default 1000;

comment on column public.tennis_orgs.label_ko is
  '온보딩·프로필에 그대로 표시되는 완성형 라벨. 비면 name_ko 로 폴백한다(JY-135).';
comment on column public.tennis_orgs.short_label is
  '칩·요약에 쓰는 짧은 라벨. 화면에 보일 문자열 그대로 넣는다(JY-135).';
comment on column public.tennis_orgs.sort_order is
  '표시 순서. 작을수록 앞. 미지정(1000)이면 name_ko·code 순으로 뒤에 붙는다(JY-135).';

-- 현재 앱 문자열 그대로 백필한다. 값이 다르면 사용자 화면 문구가 바뀐다.
-- sort_order 는 기존 Dart 배열 순서를 10 간격으로 부여해 사이에 끼울 수 있게 둔다.
update public.tennis_orgs as t
   set label_ko = v.label_ko,
       short_label = v.short_label,
       sort_order = v.sort_order
  from (values
    ('kta',   '대한테니스협회 (KTA)',                  'KTA',      10),
    ('kato',  '한국테니스발전협의회 (KATO)',           'KATO',     20),
    ('kata',  '한국동호인테니스협회 (KATA)',           'KATA',     30),
    ('ktfs',  '국민생활체육 전국테니스연합회 (KTFS)',  'KTFS',     40),
    ('kstf',  '한국시니어테니스연맹 (KSTF, 60+)',      'KSTF',     50),
    ('kssta', '한국슈퍼시니어테니스협회 (KSSTA)',      'KSSTA',    60),
    ('kasta', '단식 테니스 (KASTA / 단테매)',          'KASTA',    70),
    ('gj',    '광주광역시테니스협회 (GJTA)',           '광주협회', 80),
    ('jn',    '전라남도테니스협회 (JNTA)',             '전남협회', 90),
    ('local', '시·군 또는 클럽 자체',                  '시·군/클럽', 100)
  ) as v(code, label_ko, short_label, sort_order)
 where t.code = v.code;

-- 컬럼 추가는 기존 테이블 권한을 그대로 상속한다(신규 테이블이 아니므로 grant 불필요).
-- RLS 는 건드리지 않는다 — tennis_orgs_read(authenticated) 유지.
