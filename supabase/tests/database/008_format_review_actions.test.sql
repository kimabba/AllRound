BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(8);

INSERT INTO public.tournaments (
  id, sport, title, start_date, source, source_url, status,
  format_status, format_source_hash, format_staged, format_flags
)
VALUES
  (
    '00000000-0000-4000-8000-000000000701',
    'tennis', '승인 검수 항목', current_date, 'qa-format',
    'https://allround.invalid/format-apply', 'published',
    'needs_review', 'hash-apply',
    '{"regulation_fields":[{"label":"참가비","value":"30,000원"}],"regulation_notes":[],"description":"승인 설명"}'::jsonb,
    null
  ),
  (
    '00000000-0000-4000-8000-000000000702',
    'tennis', '경합 검수 항목', current_date, 'qa-format',
    'https://allround.invalid/format-stale', 'published',
    'needs_review', 'hash-current',
    '{"regulation_fields":[],"regulation_notes":[],"description":"오래된 설명"}'::jsonb,
    null
  ),
  (
    '00000000-0000-4000-8000-000000000703',
    'tennis', '검증 실패 항목', current_date, 'qa-format',
    'https://allround.invalid/format-reject', 'published',
    'needs_review', 'hash-reject', null,
    '[{"code":"not_in_source","field":"참가비"}]'::jsonb
  );

INSERT INTO public.crawl_documents (
  id, source, source_url, raw_html, content_hash, tournament_id
)
VALUES
  (
    '00000000-0000-4000-8000-000000000711',
    'qa-format', 'https://allround.invalid/format-apply',
    '<p>승인 원문</p>', 'hash-apply',
    '00000000-0000-4000-8000-000000000701'
  ),
  (
    '00000000-0000-4000-8000-000000000712',
    'qa-format', 'https://allround.invalid/format-stale',
    '<p>현재 원문</p>', 'hash-current',
    '00000000-0000-4000-8000-000000000702'
  ),
  (
    '00000000-0000-4000-8000-000000000713',
    'qa-format', 'https://allround.invalid/format-reject',
    '<p>검증 실패 원문</p>', 'hash-reject',
    '00000000-0000-4000-8000-000000000703'
  );

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

SELECT ok(
  public.format_apply_staged(
    '00000000-0000-4000-8000-000000000701',
    'hash-apply'
  ),
  '관리자는 현재 원문과 일치하는 staged 요강을 승인할 수 있다'
);

SELECT is(
  (SELECT description FROM public.tournaments
   WHERE id = '00000000-0000-4000-8000-000000000701'),
  '승인 설명',
  '승인된 요강 내용이 대회에 반영된다'
);

SELECT is(
  (SELECT format_status::text FROM public.tournaments
   WHERE id = '00000000-0000-4000-8000-000000000701'),
  'formatted',
  '승인된 항목은 formatted 상태가 된다'
);

SELECT isnt(
  public.format_apply_staged(
    '00000000-0000-4000-8000-000000000702',
    'hash-old'
  ),
  true,
  '오래된 source hash로는 staged 요강을 승인할 수 없다'
);

SELECT is(
  (SELECT format_status::text FROM public.tournaments
   WHERE id = '00000000-0000-4000-8000-000000000702'),
  'needs_review',
  '경합으로 거부된 항목은 검수 대기 상태를 유지한다'
);

SELECT ok(
  public.format_reject_staged(
    '00000000-0000-4000-8000-000000000703',
    'hash-reject',
    '원문 확인 필요'
  ),
  'staged 데이터가 없는 검증 실패 항목도 반려할 수 있다'
);

SELECT is(
  (SELECT format_status::text FROM public.tournaments
   WHERE id = '00000000-0000-4000-8000-000000000703'),
  'failed',
  '반려된 검증 실패 항목은 failed 상태가 된다'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT throws_ok(
  $$SELECT public.format_apply_staged(
    '00000000-0000-4000-8000-000000000702',
    'hash-current'
  )$$,
  '42501',
  'admin only',
  '일반 회원은 요강 검수 RPC를 실행할 수 없다'
);

SELECT * FROM finish();
ROLLBACK;
