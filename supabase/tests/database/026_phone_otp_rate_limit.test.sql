begin;

create extension if not exists pgtap with schema extensions;
set search_path to public, extensions;

select plan(5);

select has_function(
  'public',
  'request_phone_otp',
  array['uuid', 'text', 'text', 'integer', 'integer', 'integer', 'integer', 'integer', 'integer'],
  'OTP 발송 게이트가 번호·계정·전체 한도를 모두 받는다'
);

select is(
  public.request_phone_otp(
    '00000000-0000-4000-8000-000000000701',
    repeat('a', 64), repeat('1', 64),
    180, 0, 99, 2, 99, 99
  )->>'reason',
  'OK',
  '같은 번호의 첫 발송은 허용된다'
);

select is(
  public.request_phone_otp(
    '00000000-0000-4000-8000-000000000701',
    repeat('a', 64), repeat('2', 64),
    180, 0, 99, 2, 99, 99
  )->>'reason',
  'OK',
  '같은 번호의 일일 상한 이내 재발송은 허용된다'
);

select is(
  public.request_phone_otp(
    '00000000-0000-4000-8000-000000000702',
    repeat('a', 64), repeat('3', 64),
    180, 0, 99, 2, 99, 99
  )->>'reason',
  'PHONE_DAILY_LIMIT',
  '계정을 바꿔도 같은 번호의 일일 상한을 넘을 수 없다'
);

select is(
  (select daily_send_count from public.phone_otp where phone_hash = repeat('a', 64)),
  2,
  '차단된 요청은 번호별 발송 카운터를 증가시키지 않는다'
);

select * from finish();
rollback;
