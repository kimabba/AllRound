-- supabase/seed.sql
-- supabase db reset 시 자동 적용. (config.toml [db.seed] 의 sql_paths 기본값)

-- =========================
-- 개발용 테스트 계정
-- =========================
do $$
declare
  v_uid uuid := gen_random_uuid();
begin
  -- 이미 존재하면 건너뜀
  if exists (
    select 1 from auth.users where email = 'local-admin@allround.invalid'
  ) then
    return;
  end if;

  -- auth.users 에 삽입 (트리거가 public.users 자동 생성)
  insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password,
    email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin,
    confirmation_token, recovery_token,
    email_change, email_change_token_new, email_change_token_current
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_uid,
    'authenticated', 'authenticated',
    'local-admin@allround.invalid',
    crypt('QaLocal-Only-2026!', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Local QA Admin"}',
    false,
    '', '',
    '', '', ''
  );

  -- 관리자 권한 부여 (seed 컨텍스트는 auth session 없으므로 트리거 임시 비활성화)
  alter table public.users disable trigger users_prevent_role_self_update;
  update public.users
  set role = 'admin'
  where email = 'local-admin@allround.invalid';
  alter table public.users enable trigger users_prevent_role_self_update;
end;
$$;

-- =========================
-- rule_articles (룰북 시드)
-- =========================
insert into public.rule_articles (sport, category, title, body, order_idx) values

-- 테니스
('tennis', '서브', '서브 기본 규칙',
 '서브는 베이스라인 뒤에서 사이드라인 안쪽으로, 발이 라인을 넘지 않은 상태에서 시작합니다. 첫 서브가 폴트면 두 번째 서브를 시도하고, 두 번째 서브도 폴트면 더블폴트로 1포인트를 잃습니다. 서브 박스(상대 코트의 대각선 박스)에 정확히 들어가야 유효합니다.',
 1),

('tennis', '발리', '발리 시 라인 규칙',
 '발리(volley)는 공이 코트에 바운드되기 전에 라켓으로 치는 샷입니다. 네트를 넘기 전 또는 네트를 잡으면 즉시 실점입니다. 발 위치는 코트 안이든 밖이든 무관하며, 단지 공을 친 위치가 자기 코트 영역 내였다면 유효합니다.',
 1),

('tennis', '라인', '인/아웃 판정',
 '공이 라인에 1mm라도 닿으면 인(In)으로 판정합니다. 공이 라인 밖에 떨어지면 아웃(Out). 동호인 시합에서는 셀프 콜이 일반적이며, 의심스러운 경우 상대방 유리하게 판정하는 것이 매너입니다.',
 1),

('tennis', '점수', '게임·세트 점수 체계',
 '0(러브) → 15 → 30 → 40 → 게임. 듀스(40-40) 시 어드밴티지 받은 쪽이 다음 포인트를 따면 게임 승. 6게임을 먼저 따면 세트(단, 5-5 이후엔 7게임 또는 타이브레이크). 동호인 대회는 보통 6게임 1세트 또는 8게임 프로세트.',
 2),

('tennis', '복식', '복식 포지션 룰',
 '복식에서 서브를 받는 사람만 정해져 있고, 그 외 포지션은 자유입니다. 다만 같은 게임 내에서 리시브 포지션은 바꿀 수 없으며, 다음 게임에 가서야 변경 가능합니다. 서버는 반드시 정해진 박스로 서브를 넣어야 합니다.',
 1),

-- 풋살
('futsal', '경기 시간', '풋살 경기 시간 규칙',
 '풋살 정식 경기는 전·후반 20분씩 총 40분, 인터벌 15분입니다. 동호인 경기는 보통 25분 전·후반 또는 단판 30~40분 진행이 흔합니다. 시간이 멈춘 채로 측정되며, 마지막 1분 타임아웃 1회 가능.',
 1),

('futsal', '파울', '누적 파울 규칙',
 '한 팀이 한 하프(half) 동안 누적 파울 5개를 넘기면, 6번째 파울부터 상대팀이 직접 프리킥(2nd PK 마크 또는 파울 위치)을 얻습니다. 동호인 경기에서는 누적 파울을 적용하지 않는 경우도 많으니 사전 확인 필요.',
 1),

('futsal', '교체', '플라잉 서브 교체',
 '풋살은 경기 도중 무제한 교체가 가능합니다. 교체 박스에서만 교체할 수 있으며, 나가는 선수가 완전히 코트를 벗어난 후 들어가야 합니다. 골키퍼 교체는 데드볼 상황에서만 가능합니다.',
 1);

-- 위 3건은 로컬 검색 확인용의 옛 요약이며, 공식 룰북 30건과 중복되므로 화면에는 노출하지 않는다.
update public.rule_articles
set published = false
where sport = 'futsal'
  and title in (
    '풋살 경기 시간 규칙',
    '누적 파울 규칙',
    '플라잉 서브 교체'
  );

-- =========================
-- regions (권역 매핑 — 광주·전남 2026.05.01 분리 반영)
--   045_seed_regions.sql 이 정식 시드(ON CONFLICT DO UPDATE)이므로
--   여기서는 충돌 시 무시. enum 일관성 검사(check_enums.py)용으로 유지.
-- =========================
-- 표준 17개 광역시도. code·순서는 Dart grade_labels.dart regionCodes / enums.ts REGION_CODES 와 1:1.
-- 묶음 코드(seoul_metro 등)는 프로덕션 마이그레이션에서 is_active=false 로 유지되며 신규 seed 엔 넣지 않는다.
insert into public.regions(code, display_name_ko, governing_associations, uses_kato, uses_kata, notes) values
  ('seoul', '서울', ARRAY['kta'], true, true, '전국 단위 협회 다수(KTA·KATO·KATA).'),
  ('gyeonggi', '경기', ARRAY['kta'], true, true, '전국 단위 협회 다수.'),
  ('incheon', '인천', ARRAY['kta'], true, true, '전국 단위 협회 다수.'),
  ('gangwon', '강원', ARRAY['kta'], false, false, '도 단위 메이저 대회 중심(평창백일홍배).'),
  ('daejeon', '대전', ARRAY['kta'], false, false, '시니어연맹 별도 활성.'),
  ('sejong', '세종', ARRAY['kta'], false, false, null),
  ('chungbuk', '충북', ARRAY['kta'], false, false, null),
  ('chungnam', '충남', ARRAY['kta'], false, false, null),
  ('gwangju', '광주', ARRAY['gj'], true, true,
   '2026-05-01 전남과 분리 운영. 자체 스포츠공정위, 자체 디비전리그. 약 130 클럽 1.5만 동호인. 자체 부서: 골드/금배/일반/신인. 자체 등급 1~6급+신인.'),
  ('jeonbuk', '전북', ARRAY['kta'], false, false, '전북특별자치도.'),
  ('jeonnam', '전남', ARRAY['jn'], true, true,
   '2026-05-01 광주와 분리 운영. 시·군 협회(여수·광양·순천·목포·나주·강진·해남·영광 등) 산하. 일부 합동 대회 잔존.'),
  ('busan', '부산', ARRAY['kta'], false, false, 'KATO 비중 큼, 부산오픈챌린저 등.'),
  ('ulsan', '울산', ARRAY['kta'], false, false, null),
  ('daegu', '대구', ARRAY['kta'], false, false, '울진금강송배 KATO 전국대회 인접. 아카시아배 등 합동.'),
  ('gyeongbuk', '경북', ARRAY['kta'], false, false, null),
  ('gyeongnam', '경남', ARRAY['kta'], false, false, null),
  ('jeju', '제주', ARRAY['kta'], false, false,
   '자체 점수제(1~9), 가장 독자적. 2026 혼복 등급 미반영.')
on conflict (code) do nothing;

-- =========================
-- clubs (디렉토리 시드)
-- =========================
-- 운영 DB는 Storage 공개 URL만 허용한다. 로컬 디자인 시드는 앱에 번들된
-- `asset://` 미디어도 허용해 네트워크 없이 카드 이미지를 재현한다.
create or replace function public.club_image_urls_are_app_storage(
  p_urls text[],
  p_bucket text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    bool_and(
      u is not null
      and (
        u ~ (
          '^https://bsjdgwmveokanclqwtvx\.supabase\.co'
          || '/storage/v1/object/public/'
          || p_bucket
          || '/([0-9a-f-]{36}/)?[0-9a-f]{48}\.(jpg|png)$'
        )
        or u ~ '^asset://assets/images/clubs/(tennis|futsal)-(logo|court)\.png$'
      )
    ),
    true
  )
  from unnest(p_urls) as u;
$$;

insert into public.clubs (
  id, sport, name, region, address, contact, description,
  logo_url, intro_image_urls, status, member_count,
  meeting_days, monthly_fee, gender_preference, card_color,
  latitude, longitude
) values
('10000000-0000-4000-8000-000000000001', 'tennis', '강남 올코트 테니스', '서울 강남구', '서울 강남구 대치동', '오픈채팅 문의', '평일 저녁 복식과 주말 친선 경기를 함께합니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 32, array['화','목'], 30000, 'mixed', '#3156D8', 37.5013, 127.0396),
('10000000-0000-4000-8000-000000000002', 'tennis', '서초 라켓 메이트', '서울 서초구', '서울 서초구 반포동', '오픈채팅 문의', '초급자도 편하게 참여하는 주말 테니스 모임입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 21, array['토'], 25000, 'mixed', '#176B63', 37.5048, 127.0032),
('10000000-0000-4000-8000-000000000003', 'tennis', '분당 베이스라인', '경기 성남시', '경기 성남시 분당구', '오픈채팅 문의', '분당권 직장인이 모여 주 2회 정기 운동을 합니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 28, array['수','일'], 30000, 'mixed', '#6941C6', 37.3827, 127.1189),
('10000000-0000-4000-8000-000000000004', 'tennis', '송도 에이스 클럽', '인천 연수구', '인천 연수구 송도동', '오픈채팅 문의', '실력보다 매너를 우선하는 혼성 복식 클럽입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 18, array['금','일'], 25000, 'mixed', '#18376D', 37.3824, 126.6564),
('10000000-0000-4000-8000-000000000005', 'tennis', '대전 스매시 크루', '대전 유성구', '대전 유성구 전민동', '오픈채팅 문의', '초중급 중심의 평일 야간 테니스 크루입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 24, array['월','목'], 20000, 'mixed', '#A15C08', 36.3994, 127.4000),
('10000000-0000-4000-8000-000000000006', 'tennis', '광주 챔피언 테니스', '광주 서구', '광주 서구 풍암동', '오픈채팅 문의', '광주 생활체육 대회와 정기 복식에 참여합니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 38, array['화','토'], 20000, 'mixed', '#C2413B', 35.1260, 126.8794),
('10000000-0000-4000-8000-000000000007', 'tennis', '순천 그린코트', '전남 순천시', '전남 순천시 연향동', '오픈채팅 문의', '토요일 오전 누구나 참여할 수 있는 친선 모임입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 26, array['토'], 15000, 'mixed', '#176B63', 34.9507, 127.4872),
('10000000-0000-4000-8000-000000000008', 'tennis', '부산 오션 라켓', '부산 해운대구', '부산 해운대구 좌동', '오픈채팅 문의', '해운대권 직장인과 주말 복식을 즐기는 클럽입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 30, array['수','일'], 30000, 'mixed', '#3156D8', 35.1728, 129.1742),
('10000000-0000-4000-8000-000000000009', 'tennis', '대구 탑스핀', '대구 수성구', '대구 수성구 범어동', '오픈채팅 문의', '기초 레슨과 게임을 함께 운영하는 테니스 모임입니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 22, array['목','토'], 25000, 'mixed', '#6941C6', 35.8582, 128.6308),
('10000000-0000-4000-8000-000000000010', 'tennis', '제주 선샤인 테니스', '제주 제주시', '제주 제주시 연동', '오픈채팅 문의', '제주에서 아침 운동과 월 1회 교류전을 엽니다.', 'asset://assets/images/clubs/tennis-logo.png', array['asset://assets/images/clubs/tennis-court.png'], 'approved', 19, array['토','일'], 20000, 'mixed', '#A15C08', 33.4890, 126.4983),
('20000000-0000-4000-8000-000000000001', 'futsal', '잠실 풋살 러너스', '서울 송파구', '서울 송파구 잠실동', '오픈채팅 문의', '주말 저녁 꾸준히 함께 뛰는 생활체육 풋살팀입니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 27, array['토'], 30000, 'mixed', '#3156D8', 37.5111, 127.0980),
('20000000-0000-4000-8000-000000000002', 'futsal', '마포 시티 파이브', '서울 마포구', '서울 마포구 망원동', '오픈채팅 문의', '초중급 중심으로 매주 수요일 저녁에 운동합니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 20, array['수'], 25000, 'mixed', '#C2413B', 37.5560, 126.9020),
('20000000-0000-4000-8000-000000000003', 'futsal', '수원 블루킥', '경기 수원시', '경기 수원시 영통구', '오픈채팅 문의', '매너 있는 경기와 체력 향상을 목표로 합니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 24, array['화','금'], 30000, 'mixed', '#18376D', 37.2596, 127.0465),
('20000000-0000-4000-8000-000000000004', 'futsal', '송도 유나이티드', '인천 연수구', '인천 연수구 송도동', '오픈채팅 문의', '남녀 모두 참여하는 금요일 야간 풋살팀입니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 18, array['금'], 25000, 'mixed', '#176B63', 37.3824, 126.6564),
('20000000-0000-4000-8000-000000000005', 'futsal', '대전 레드폭스 FC', '대전 유성구', '대전 유성구 관평동', '오픈채팅 문의', '초급자와 복귀자를 환영하는 주말 풋살팀입니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 21, array['일'], 20000, 'mixed', '#C2413B', 36.4242, 127.3880),
('20000000-0000-4000-8000-000000000006', 'futsal', '광주 풋살 라이온즈', '광주 북구', '광주 북구 용봉동', '오픈채팅 문의', '광주권 친선 경기와 월간 교류전을 운영합니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 31, array['목','일'], 30000, 'mixed', '#A15C08', 35.1762, 126.9111),
('20000000-0000-4000-8000-000000000007', 'futsal', '순천 프렌즈 FC', '전남 순천시', '전남 순천시 조례동', '오픈채팅 문의', '즐겁고 안전한 경기를 우선하는 혼성 풋살팀입니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 16, array['토'], 15000, 'mixed', '#176B63', 34.9636, 127.5220),
('20000000-0000-4000-8000-000000000008', 'futsal', '부산 웨이브 풋살', '부산 해운대구', '부산 해운대구 우동', '오픈채팅 문의', '해운대 야간 리그에 함께 참가할 팀원을 찾습니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 29, array['수','토'], 30000, 'mixed', '#3156D8', 35.1631, 129.1636),
('20000000-0000-4000-8000-000000000009', 'futsal', '대구 골메이커스', '대구 수성구', '대구 수성구 만촌동', '오픈채팅 문의', '포지션 상관없이 즐겁게 뛰는 직장인 팀입니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 23, array['월','목'], 25000, 'mixed', '#6941C6', 35.8583, 128.6507),
('20000000-0000-4000-8000-000000000010', 'futsal', '제주 오렌지 FC', '제주 제주시', '제주 제주시 노형동', '오픈채팅 문의', '제주 생활체육 풋살과 주말 친선전을 함께합니다.', 'asset://assets/images/clubs/futsal-logo.png', array['asset://assets/images/clubs/futsal-court.png'], 'approved', 17, array['일'], 20000, 'mixed', '#A15C08', 33.4858, 126.4769)
on conflict (id) do update set
  sport = excluded.sport,
  name = excluded.name,
  region = excluded.region,
  address = excluded.address,
  contact = excluded.contact,
  description = excluded.description,
  logo_url = excluded.logo_url,
  intro_image_urls = excluded.intro_image_urls,
  status = excluded.status,
  member_count = excluded.member_count,
  meeting_days = excluded.meeting_days,
  monthly_fee = excluded.monthly_fee,
  gender_preference = excluded.gender_preference,
  card_color = excluded.card_color,
  latitude = excluded.latitude,
  longitude = excluded.longitude;

-- 일반 앱에서도 디자인 프리뷰의 "나의 클럽"과 팀원 모집 섹션을 그대로
-- 확인할 수 있게 로컬 QA 계정에 샘플 멤버십과 모집글을 연결한다.
do $$
declare
  v_local_user_id uuid;
begin
  select id
  into v_local_user_id
  from public.users
  where email = 'local-admin@allround.invalid';

  if v_local_user_id is null then
    raise exception 'local seed user is missing';
  end if;

  insert into public.club_members (club_id, user_id, role, status) values
    ('10000000-0000-4000-8000-000000000001', v_local_user_id, 'member', 'active'),
    ('10000000-0000-4000-8000-000000000004', v_local_user_id, 'member', 'active'),
    ('20000000-0000-4000-8000-000000000001', v_local_user_id, 'member', 'active'),
    ('20000000-0000-4000-8000-000000000004', v_local_user_id, 'member', 'active')
  on conflict (club_id, user_id) do update set
    role = excluded.role,
    status = excluded.status,
    left_at = null;

  insert into public.club_recruiting_posts (
    id, club_id, created_by, title, intro, place, schedule_text,
    skill_level, gender_text, age_text, position_text,
    field_count, keeper_count, total_count, cost_text, status, created_at
  ) values
    (
      '30000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000001',
      v_local_user_id,
      '토요일 저녁 필드 플레이어 모집',
      '기본 매너를 지키며 꾸준히 함께할 멤버를 찾습니다.',
      '잠실 풋살장', '매주 토요일 19:00', '초중급', '무관', '20–40대', '필드',
      3, 1, 4, '회당 1만원', 'open', '2026-08-15 10:00:00+09'
    ),
    (
      '30000000-0000-4000-8000-000000000002',
      '20000000-0000-4000-8000-000000000002',
      v_local_user_id,
      '평일 저녁 회원 모집',
      '즐겁게 오래 함께할 팀원을 찾습니다.',
      '망원 풋살장', '매주 수요일 20:00', '중급', '여성', '30–50대', '필드',
      4, 0, 4, '월 2.5만원', 'open', '2026-08-16 10:00:00+09'
    ),
    (
      '30000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000001',
      v_local_user_id,
      '주말 복식 신규 회원 모집',
      '기본 매너를 지키며 꾸준히 함께할 회원을 찾습니다.',
      '대치 테니스장', '매주 토요일 09:00', '신입–3부', '혼성', '20–40대', '복식',
      4, 0, 4, '월 3만원', 'open', '2026-08-17 10:00:00+09'
    ),
    (
      '30000000-0000-4000-8000-000000000004',
      '10000000-0000-4000-8000-000000000002',
      v_local_user_id,
      '평일 저녁 회원 모집',
      '즐겁게 오래 함께할 테니스 회원을 찾습니다.',
      '반포 테니스장', '매주 목요일 20:00', '4부–신입', '여성', '30–50대', '복식',
      3, 0, 3, '월 2.5만원', 'open', '2026-08-18 10:00:00+09'
    )
  on conflict (id) do update set
    club_id = excluded.club_id,
    created_by = excluded.created_by,
    title = excluded.title,
    intro = excluded.intro,
    place = excluded.place,
    schedule_text = excluded.schedule_text,
    skill_level = excluded.skill_level,
    gender_text = excluded.gender_text,
    age_text = excluded.age_text,
    position_text = excluded.position_text,
    field_count = excluded.field_count,
    keeper_count = excluded.keeper_count,
    total_count = excluded.total_count,
    cost_text = excluded.cost_text,
    status = excluded.status,
    closed_at = null,
    created_at = excluded.created_at;
end;
$$;

-- 멤버십 트리거가 샘플 클럽의 표시용 인원수를 1명으로 다시 계산하므로,
-- 프리뷰 카드와 같은 디렉토리 인원수로 마지막에 복원한다.
update public.clubs as club
set member_count = sample.member_count
from (values
  ('10000000-0000-4000-8000-000000000001'::uuid, 32),
  ('10000000-0000-4000-8000-000000000004'::uuid, 18),
  ('20000000-0000-4000-8000-000000000001'::uuid, 27),
  ('20000000-0000-4000-8000-000000000004'::uuid, 18)
) as sample(id, member_count)
where club.id = sample.id;

-- =========================
-- 샘플 published 대회 (개발용 시드)
--   실제 운영 시에는 삭제하거나 status='draft' 로 시작
-- =========================
insert into public.tournaments (
  sport, title, organizer, description,
  start_date, application_deadline, region, location,
  region_code, host_associations,
  division_label_local, entry_fee_unit,
  eligible_grades, entry_fee, prize, format,
  source, status
) values
('tennis', '광주광역시장배 동호인 테니스 대회', '광주광역시테니스협회(GJTA)',
 '2026년 광주·전남 분리 후 광주협회 단독 주최. 신입~3부 부수별 단·복식.',
 (current_date + interval '14 days')::date,
 (current_date + interval '7 days')::date,
 '광주', '광주 시민체육관 테니스장',
 'gwangju', ARRAY['광주광역시테니스협회'],
 '남자 일반부 (1~5급) + 여자 신인부', 'per_team',
 array['under1y','y1to3','y3to5'],
 30000, '부수별 1·2·3위 시상',
 '단·복식 토너먼트',
 'manual', 'published'),

('tennis', '전남 신년 오픈 단식', '전라남도테니스협회',
 '2026 분리 후 전남협회 단독 운영. 오픈(1부) 단식 토너먼트.',
 (current_date + interval '21 days')::date,
 (current_date + interval '14 days')::date,
 '전남', '전남 무안종합체육시설',
 'jeonnam', ARRAY['전라남도테니스협회'],
 '남자 오픈부', 'per_person',
 array['over5y','y3to5'],
 50000, '우승 200만원',
 '단식 토너먼트',
 'manual', 'published'),

('tennis', '4·5부 친선 복식 대회', '서울 라켓 클럽',
 '서울 직장인 동호인 대상 4·5부 복식.',
 (current_date + interval '10 days')::date,
 (current_date + interval '5 days')::date,
 '서울', '서울 양재 테니스장',
 'seoul_metro', ARRAY['서울 라켓 클럽 (KATA 등록)'],
 '4·5부', 'per_team',
 array['under1y','y1to3'],
 20000, '간식·선물',
 '복식 풀리그',
 'manual', 'published'),

('futsal', '주말 풋살 챌린지컵 (중급)', '광주 풋살 라이언즈',
 '중급 동호인 풋살 단판 토너먼트.',
 (current_date + interval '12 days')::date,
 (current_date + interval '7 days')::date,
 '광주', '광주 스포츠 풋살파크',
 'gwangju', ARRAY['광주 풋살 라이언즈'],
 null, 'per_team',
 array['intermediate','advanced'],
 40000, '1·2위 시상',
 '5인제 토너먼트',
 'manual', 'published'),

('futsal', '초급 풋살 입문 리그', '서울 풋볼 클럽 FC',
 '풋살 입문자 환영. 안전 제일.',
 (current_date + interval '20 days')::date,
 (current_date + interval '14 days')::date,
 '서울', '서울 잠실 실내 풋살장',
 'seoul_metro', ARRAY['서울 풋볼 클럽 FC'],
 null, 'per_team',
 array['beginner','intermediate'],
 25000, null,
 '리그전',
 'manual', 'published');
