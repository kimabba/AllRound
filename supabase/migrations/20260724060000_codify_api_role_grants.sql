-- API 롤 권한을 마이그레이션에 codify (재현성 스냅샷)
--
-- 문제: 마이그레이션 체인만으로는 동작하는 DB 를 재현할 수 없었다. 마이그레이션이
--   anon/authenticated/service_role 에 테이블 DML·함수 EXECUTE 를 부여하지 않기 때문이다.
--   프로덕션은 프로젝트 생성 시의 기본권한(pg_default_acl)으로 갖고 있어 동작하지만,
--   마이그레이션만으로 만든 DB(CI·클린 재생·스테이징·DR)는 앱이 통째로 막힌다.
--
-- 원인 위치(2026-07-24 실측): pg_default_acl 의 "FOR ROLE postgres" 항목.
--   마이그레이션 객체는 postgres 가 만드는데,
--     프로덕션 : 테이블에 DML 전체 + 함수 EXECUTE 를 API 롤에 자동 부여
--     로컬/신규: 테이블은 MAINTAIN/REFERENCES/TRIGGER/TRUNCATE 만, 함수는 없음
--   (supabase_admin 항목은 양쪽 동일하지만 객체 소유자가 아니라 무관하다.)
--   Supabase 공식 변경: 신규 프로젝트 2026-05-30 부터 기본, 기존 프로젝트는 2026-10-30 적용 예정.
--   → 그 날 이후 새 객체는 프로덕션에서도 자동 권한이 붙지 않는다. 이 파일은 그 전환의 첫 단계다.
--
-- 왜 "전부 grant" 가 아니라 이 범위인가:
--   실측으로 필요한 델타는 딱 두 가지였다.
--     (1) 테이블·시퀀스 DML — 프로덕션 기본권한이 주던 것.
--     (2) service_role 함수 EXECUTE — 마이그레이션이 트리거 함수를 public 에서 revoke 하는 순간
--         PUBLIC 기본 EXECUTE 가 사라지는데, 클린 재생에는 service_role 명시 grant 가 없어 같이 잃는다.
--   anon/authenticated 의 함수 EXECUTE 는 여기서 부여하지 않는다. 부여하면 앞선 마이그레이션들이
--   의도적으로 걷어낸 제한(트리거 함수·auth hook·delete_account_data 등)을 되살려
--   보안 테스트 005/006/007 이 실제로 깨진다(실측 확인). 미부여분은 ACL 이 비어 있는 함수의
--   PUBLIC 기본 EXECUTE 로 프로덕션과 동일하게 동작한다.
--
-- 프로덕션 적용 시 no-op 이어야 한다. 적용 전후 권한 지문을 비교해 증명한다:
--   scripts/db/grant_fingerprint.sql
--
-- 앞으로의 규칙: 새 테이블·함수를 만드는 마이그레이션은 같은 파일에서 grant 를 명시한다.
--   (docs/rules/DATABASE_RULES.md · 가드 테스트 011_api_role_grants.test.sql)

begin;

-- pgvector 등 확장 소유 객체는 grant 대상이 아니라 "no privileges were granted" WARNING 이
-- 100줄 넘게 쏟아진다. 의미 없는 노이즈만 억제한다(ERROR 는 그대로 보인다).
set local client_min_messages = error;

grant usage on schema public to anon, authenticated, service_role;

-- 테이블·뷰·시퀀스: 프로덕션 실측과 동일(테이블 40 + 뷰 1 전권, 시퀀스 1).
-- 행 단위 통제는 RLS 가 한다 — public 테이블 42개 전부 RLS 활성 + 정책 보유를 확인했다.
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;

-- 프로덕션 예외: 클럽 문의는 조회만 열고 쓰기는 서버(Edge) 경로 전용.
-- 20260716211500_club_inquiries.sql 이 같은 패턴을 선언한다. 여기서도 동일하게 유지한다.
revoke insert, update, delete on public.club_inquiry_threads, public.club_inquiry_messages
  from anon, authenticated;

-- 함수: service_role 만. 프로덕션은 182/182 보유이므로 적용 시 no-op.
grant execute on all functions in schema public to service_role;

commit;
