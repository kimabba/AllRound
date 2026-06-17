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
  if exists (select 1 from auth.users where email = 'ssfak@naver.com') then
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
    'ssfak@naver.com',
    crypt('pass1234', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"ssfak"}',
    false,
    '', '',
    '', '', ''
  );

  -- 관리자 권한 부여 (seed 컨텍스트는 auth session 없으므로 트리거 임시 비활성화)
  alter table public.users disable trigger users_prevent_role_self_update;
  update public.users set role = 'admin' where email = 'ssfak@naver.com';
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

-- =========================
-- regions (권역 매핑 — 광주·전남 2026.05.01 분리 반영)
--   045_seed_regions.sql 이 정식 시드(ON CONFLICT DO UPDATE)이므로
--   여기서는 충돌 시 무시. enum 일관성 검사(check_enums.py)용으로 유지.
-- =========================
insert into public.regions(code, display_name_ko, governing_associations, uses_kato, uses_kata, notes) values
  ('gwangju', '광주', ARRAY['KTA-광주(GJTA)'], false, false,
   '2026-05-01 전남과 분리 운영. 자체 스포츠공정위, 자체 디비전리그. 약 130 클럽 1.5만 동호인. 자체 부서: 골드/금배/일반/신인. 자체 등급 1~6급+신인.'),
  ('jeonnam', '전남', ARRAY['KTA-전남'], false, false,
   '2026-05-01 광주와 분리 운영. 시·군 협회(여수·광양·순천·목포·나주·강진·해남·영광 등) 산하. 일부 합동 대회 잔존.'),
  ('seoul_metro', '수도권', ARRAY['KTA-서울','KTA-경기','KTA-인천'], true, true,
   'KATA 본부 위치. 동호인 1인이 KATA+KATO+KTA 동시 등록 일반.'),
  ('busan_ulsan_gn', '부산·울산·경남', ARRAY['KTA-부산','KTA-울산','KTA-경남'], true, false,
   'KATO 비중 큼, 부산오픈챌린저 등.'),
  ('daegu_gb', '대구·경북', ARRAY['KTA-대구','KTA-경북'], true, false,
   '울진금강송배 KATO 전국대회. 아카시아배 등 합동.'),
  ('chungcheong', '충청', ARRAY['KTA-대전','KTA-충남','KTA-충북','KTA-세종'], false, false,
   '시니어연맹 별도 활성.'),
  ('gangwon', '강원', ARRAY['KTA-강원'], false, false,
   '도 단위 메이저 대회 중심(평창백일홍배).'),
  ('jeju', '제주', ARRAY['KTA-제주'], false, false,
   '자체 점수제(1~9), 가장 독자적. 2026 혼복 등급 미반영.')
on conflict (code) do nothing;

-- =========================
-- clubs (디렉토리 시드)
-- =========================
insert into public.clubs (sport, name, region, address, contact, description) values
('tennis', '광주 메이저 테니스 클럽', '광주', '광주광역시 서구 ○○동',
  '광주 ○○ 코트 (오픈채팅 링크 별도)',
  '주말 단·복식 정기 게임. 신입~3부 환영. 주 2회 정기 운영.'),
('tennis', '전남 화이트 테니스 동호회', '전남', '전남 순천시 ○○동',
  '단톡 운영 (가입 문의)',
  '4부~신입 위주. 매주 토요일 오전 정기 게임.'),
('tennis', '서울 강남 라켓 클럽', '서울', '서울 강남구 ○○동',
  'kakao @racketclub',
  '평일 저녁 직장인 모임. 1~3부.'),
('futsal', '광주 풋살 라이언즈', '광주', '광주광역시 동구 ○○구장',
  '인스타 @gj_futsal_lions',
  '매주 일요일 오후 정기 풋살. 초·중급 환영. 5인제.'),
('futsal', '서울 풋볼 클럽 FC', '서울', '서울 성동구 ○○구장',
  'naver cafe',
  '주중 야간 풋살, 중급 이상.');

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
