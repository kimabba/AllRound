-- 서버 경로 전용 함수의 클라이언트 실행 권한 회수 (#379)
--
-- 배경: #377 에서 replace_org_ranking_division 이 anon 에게 열린 채 프로덕션에 올라갔다.
--   Supabase 는 새 함수에 anon·authenticated 개별 grant 를 주므로, 마이그레이션의
--   `revoke ... from public` 만으로는 막히지 않는다. 그래서 나머지 함수도 전수로 확인했다.
--
-- 전수 조회(has_function_privilege 로 실효 권한) 결과, 클라이언트에 열려 있던 나머지는
-- 대부분 의도된 것이었다:
--   - 본인 데이터 조작 RPC(block_user, bind_my_device_token, save_user_sports …)
--   - 내부에서 권한을 재검사하는 관리자·운영진 RPC(admin_*, tournaments_bulk_*,
--     format_*_staged, *_club_dues_* — 전부 is_admin() 또는 매니저 확인 후 raise)
--   - RLS 정책이 참조하는 헬퍼(is_admin, is_*_club_*, has_verified_signup_age …)
--     → 이건 오히려 회수하면 안 된다. 정책 표현식은 호출자 권한으로 평가되므로
--       EXECUTE 가 없으면 정책이 42501 로 죽는다(#365 가 같은 뿌리의 반대 방향).
--
-- 이 마이그레이션이 회수하는 것은 두 종류다.
--
-- 1) 트리거 전용 함수 — RPC 로 노출될 이유가 없다.
--    실제 위험은 낮다(Postgres 가 직접 호출을 거부한다: "trigger functions can only be
--    called as triggers"). 다만 011_api_role_grants 의 주석이 밝히듯 이 프로젝트의 모델은
--    "트리거 함수는 revoke 하고 service_role 에 명시 부여"이고, 007 이 이미 두 개를 그렇게
--    처리했다. 나머지가 빠져 있어 모델이 어긋나 있었고, secdef 인
--    enforce_club_inquiry_text_policy 는 advisor 경고로도 남아 있었다.
--    트리거 발동 시점에는 호출자의 EXECUTE 를 재검사하지 않으므로 회수해도 트리거는 돈다
--    (권한 검사는 CREATE TRIGGER 시점 1회).
--
-- 2) 크롤러 잠금 함수(crawl_try_start / crawl_release) — 서버(크롤러) 전용 경로다.
--    SECURITY INVOKER 라 crawl_sources 의 RLS(admin·service_role 만)에 막혀 anon 이 불러도
--    0행이지만, 열어 둘 이유가 없다.
--
-- 함정: `from public` 만 쓰면 개별 grant 가 남고, `from anon` 만 쓰면 PUBLIC 경유가 남는다.
--   둘 다 떼야 한다. 그러면 PUBLIC 경유로만 권한을 갖던 service_role 도 함께 잃으므로
--   다시 명시 부여한다(011 테스트 3 이 이걸 지킨다).

begin;

-- ── 1) 트리거 전용 함수 ──────────────────────────────────────────────
revoke execute on function
  public.enforce_club_inquiry_text_policy(),
  public.enforce_active_grade(),
  public.enforce_eligible_grade_format(),
  public.enforce_min_signup_age(),
  public.enforce_user_division_is_ranking_grade(),
  public.invalidate_rule_embedding(),
  public.invalidate_tournament_embedding(),
  public.prevent_notification_content_update(),
  public.prevent_role_self_update(),
  public.touch_updated_at(),
  public.update_club_member_count()
  from public, anon, authenticated;

grant execute on function
  public.enforce_club_inquiry_text_policy(),
  public.enforce_active_grade(),
  public.enforce_eligible_grade_format(),
  public.enforce_min_signup_age(),
  public.enforce_user_division_is_ranking_grade(),
  public.invalidate_rule_embedding(),
  public.invalidate_tournament_embedding(),
  public.prevent_notification_content_update(),
  public.prevent_role_self_update(),
  public.touch_updated_at(),
  public.update_club_member_count()
  to service_role;

-- ── 2) 크롤러 잠금 함수 ─────────────────────────────────────────────
revoke execute on function
  public.crawl_try_start(text),
  public.crawl_release(text)
  from public, anon, authenticated;

grant execute on function
  public.crawl_try_start(text),
  public.crawl_release(text)
  to service_role;

commit;
