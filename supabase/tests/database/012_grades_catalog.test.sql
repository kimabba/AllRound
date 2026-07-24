-- JY-146 P3-a: 등급 사전(grades)이 정본으로 동작하는지 검증한다.
-- CHECK 제약을 FK 로 바꿨으므로, 잘못된 등급이 거부되는 경로가 실제로 살아 있는지가 핵심.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(26);

-- 1) 사전 내용 — 종목별 등급 수와 순서.
SELECT is(
  (SELECT count(*) FROM public.grades WHERE sport = 'tennis' AND is_active),
  4::bigint,
  '테니스 등급 4개가 활성 상태다'
);
SELECT is(
  (SELECT count(*) FROM public.grades WHERE sport = 'futsal' AND is_active),
  5::bigint,
  '풋살 등급 5개가 활성 상태다'
);
SELECT is(
  (SELECT string_agg(code, ',' ORDER BY sort_order)
     FROM public.grades WHERE sport = 'futsal' AND is_active),
  'intro,beginner,intermediate,advanced,elite',
  '풋살 등급이 입문→선출 순서로 정렬된다'
);
SELECT is(
  (SELECT label_ko FROM public.grades WHERE sport = 'futsal' AND code = 'elite'),
  '선출',
  '라벨이 DB 에 있다(그동안 코드에만 있던 축)'
);

-- 2) CHECK → FK 교체가 실제로 일어났는지.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.user_sports'::regclass
       AND conname = 'user_sports_grade_check'
  ),
  '옛 CHECK 제약(user_sports_grade_check)이 제거됐다'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.user_sports'::regclass
       AND conname = 'user_sports_grade_fkey'
       AND contype = 'f'
  ),
  'user_sports 가 grades 를 복합 FK 로 참조한다'
);

-- 3) 강제력 — 사전에 없는 등급, 그리고 종목이 어긋난 등급을 거부해야 한다.
--    후자가 복합 FK 의 핵심이다. 단일 컬럼 FK 였다면 풋살 사용자에게 테니스 등급을
--    붙일 수 있다. BEFORE 트리거(활성 등급 강제)가 FK 보다 먼저 걸리므로 기대 코드는
--    23514 다 — FK 는 그 뒤의 방어선이고, 존재 자체는 위 pg_constraint 검사가 지킨다.
--    (INSERT 는 (user_id, sport) PK 충돌이 먼저 나서 제약까지 가지 않으므로 UPDATE 로 검증한다.)
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'div5'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '사전에 없는 등급(폐기된 div5)은 거부된다'
);
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'under1y'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '테니스 등급을 풋살에 붙이면 거부된다(종목 간 교차 오염 차단)'
);

-- 4) 폐기 등급 — FK 는 "존재"만 보므로 트리거가 신규 배정을 막아야 한다.
--    기존 행은 남겨야 하므로(과거 데이터 보존) FK 로는 표현할 수 없는 규칙이다.
UPDATE public.grades SET is_active = false WHERE sport = 'futsal' AND code = 'elite';
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'elite'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '폐기된(is_active=false) 등급은 새로 배정할 수 없다'
);
SELECT lives_ok(
  $$UPDATE public.grades SET is_active = false WHERE sport = 'futsal' AND code = 'beginner'$$,
  '이미 그 등급을 쓰는 사용자가 있어도 폐기 처리는 가능하다(기존 행 보존)'
);
-- 폐기된 등급을 이미 가진 사용자가 프로필의 다른 값을 저장해도 막히면 안 된다.
-- (트리거 WHEN 절이 없으면 값이 그대로여도 발동해 저장 자체가 실패한다.)
SELECT lives_ok(
  $$UPDATE public.user_sports SET grade = grade, is_primary = is_primary
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '폐기 등급을 가진 기존 행은 값이 그대로면 재저장할 수 있다'
);
-- 앱의 실제 저장 경로는 UPDATE 가 아니라 upsert 다(saveUserSports). Postgres 는 충돌
-- 해소 전에 BEFORE INSERT 를 먼저 발동시키므로, UPDATE 경로만 검증하면 실사용에서
-- 막히는 걸 놓친다. 예전 delete+insert 구현에서는 DELETE 만 커밋된 채 INSERT 가 거부돼
-- 사용자의 종목 정보가 통째로 사라졌다.
SELECT lives_ok(
  $$INSERT INTO public.user_sports (user_id, sport, grade, is_primary)
    VALUES ('00000000-0000-4000-8000-000000000005', 'futsal', 'beginner', false)
    ON CONFLICT (user_id, sport) DO UPDATE
      SET grade = excluded.grade, is_primary = excluded.is_primary$$,
  '폐기 등급 보유자가 upsert 로 프로필을 재저장할 수 있다(앱 실제 경로)'
);
-- 보존은 "그 사용자가 이미 갖고 있던 값"에만 적용된다. 폐기 등급을 남에게 새로
-- 붙이는 건 여전히 막혀야 한다 — 그러지 않으면 트리거가 무력화된다.
SELECT throws_ok(
  $$INSERT INTO public.user_sports (user_id, sport, grade, is_primary)
    VALUES ('00000000-0000-4000-8000-000000000006', 'futsal', 'beginner', false)
    ON CONFLICT (user_id, sport) DO UPDATE SET grade = excluded.grade$$,
  '23514',
  NULL,
  '폐기 등급은 보유자가 아닌 사용자에게 새로 배정할 수 없다'
);
-- 앱의 실제 저장 진입점은 save_user_sports RPC 다(단일 트랜잭션).
-- 폐기 등급 보유자가 이 경로로 프로필을 저장할 수 있어야 한다.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
SELECT lives_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"tennis","grade":"y1to3","is_primary":true},
        {"sport":"futsal","grade":"beginner","is_primary":false}]'::jsonb)$$,
  '폐기 등급 보유자가 RPC 로 프로필을 저장할 수 있다(앱 실제 경로)'
);
-- 주 종목 교체는 행 순서에 무관해야 한다. one_primary_per_user 는 (user_id) WHERE
-- is_primary 부분 유니크 인덱스라, 새 주 종목을 먼저 올리는 배치는 23505 로 죽었다.
SELECT lives_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"beginner","is_primary":true},
        {"sport":"tennis","grade":"y1to3","is_primary":false}]'::jsonb)$$,
  '새 주 종목이 배열 앞에 와도 주 종목을 교체할 수 있다'
);
SELECT is(
  (SELECT sport::text FROM public.user_sports
    WHERE user_id = '00000000-0000-4000-8000-000000000005' AND is_primary),
  'futsal',
  '주 종목이 실제로 교체됐다'
);
-- 목록에서 빠진 종목만 지운다.
SELECT lives_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"beginner","is_primary":true}]'::jsonb)$$,
  '종목을 하나로 줄일 수 있다'
);
SELECT is(
  (SELECT string_agg(sport::text, ',' ORDER BY sport::text)
     FROM public.user_sports WHERE user_id = '00000000-0000-4000-8000-000000000005'),
  'futsal',
  '목록에서 빠진 종목만 삭제된다'
);
-- 동시 저장 직렬화. 두 기기·재시도로 같은 사용자가 동시에 주 종목을 바꾸면, 뒤 요청의
-- 스냅샷이 앞 요청의 새 primary 행을 못 봐 부분 유니크 인덱스에서 23505 로 죽는다.
-- pgTAP 은 단일 세션이라 경합 자체는 재현할 수 없으므로, 락을 실제로 잡는지까지 고정한다
-- (직렬화 동작은 두 세션 스크립트로 별도 확인했다: 선행 락 해제까지 대기).
-- 이 세션(pid)에서, uid 로 계산한 바로 그 키의 락인지까지 본다. granted advisory lock 이
-- 하나라도 있으면 통과하게 두면 다른 세션의 무관한 락이나 상수 키 락도 통과한다.
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_locks
     WHERE locktype = 'advisory'
       AND pid = pg_backend_pid()
       AND granted
       AND ((classid::bigint << 32) | objid::bigint)
           = hashtextextended('00000000-0000-4000-8000-000000000005', 0)
  ),
  'RPC 가 uid 로 계산한 키의 advisory lock 을 이 세션에서 잡는다(동시 저장 직렬화)'
);
-- 배열 불변식은 쓰기 전에 검사한다. 안 하면 21000/23505 같은 내부 오류로 끝나
-- 클라이언트가 무엇을 고쳐야 할지 알 수 없다.
SELECT throws_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"beginner"},{"sport":"futsal","grade":"intro"}]'::jsonb)$$,
  '22023',
  NULL,
  '같은 종목이 두 번 들어오면 거부된다'
);
SELECT throws_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"beginner","is_primary":true},
        {"sport":"tennis","grade":"y1to3","is_primary":true}]'::jsonb)$$,
  '22023',
  NULL,
  '주 종목이 둘이면 거부된다'
);
SELECT throws_ok(
  $$SELECT public.save_user_sports('[{"grade":"beginner"}]'::jsonb)$$,
  '22023',
  NULL,
  'sport 가 없는 원소는 거부된다'
);
RESET ROLE;

UPDATE public.grades SET is_active = true WHERE sport = 'futsal';

-- 5) RLS — 선택지 표시는 되어야 하고, 사전 수정은 관리자만.
--    관리자 경로가 통째로 막혀도 통과하지 않도록 성공 경로까지 확인한다.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
SELECT is(
  (SELECT count(*) FROM public.grades),
  9::bigint,
  '로그인 사용자는 등급 사전을 읽는다'
);
SELECT throws_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('futsal', 'hacked', '침입', 99)$$,
  '42501',
  NULL,
  '일반 사용자는 등급 사전에 쓸 수 없다'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
SELECT lives_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('futsal', 'qa_probe', 'QA', 99)$$,
  '관리자는 등급을 추가할 수 있다(운영 경로 — 등급 관리가 INSERT 로 끝난다)'
);
-- 관리자 INSERT 가 운영 경로인 이상, 종목 간 code 중복은 DB 가 막아야 한다.
-- 클라이언트 라벨 맵이 code 단일 키라 겹치면 한쪽이 다른 종목 라벨을 덮어쓴다.
SELECT throws_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('tennis', 'advanced', '상급', 9)$$,
  '23505',
  NULL,
  '다른 종목이 이미 쓰는 code 는 추가할 수 없다'
);

SELECT * FROM finish();
ROLLBACK;
