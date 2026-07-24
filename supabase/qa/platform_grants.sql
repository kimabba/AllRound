-- Supabase 플랫폼 기본권한 재현 (테스트/로컬 전용 부트스트랩)
--
-- 왜 필요한가: 이 저장소의 마이그레이션은 API 롤(anon/authenticated/service_role)에
--   테이블 DML·함수 EXECUTE 를 부여하지 않는다. 프로덕션은 Supabase 프로젝트 생성 시의
--   기본권한으로 이미 갖고 있어서 동작하지만, 마이그레이션만으로 만든 DB(=CI·클린 재생)는
--   그 baseline 이 없어 대부분의 pgTAP 가 "permission denied" 로 죽는다.
--   → 마이그레이션 체인만으로는 동작하는 DB 를 재현할 수 없다(별도 과제).
--      여기서는 테스트가 프로덕션과 같은 출발선에 서도록 그 baseline 만 보충한다.
--
-- 이 파일은 프로덕션에 적용하지 않는다. 스키마·정책을 바꾸지 않고 권한만 맞춘다.
--
-- 값의 근거(2026-07-24 프로덕션 실측):
--   - 테이블 42개 전부 anon/authenticated/service_role SELECT 보유
--   - authenticated INSERT 미보유 테이블은 club_inquiry_threads/messages 2개뿐(쓰기는 Edge 전용)
--   - 함수 182개 전부 service_role EXECUTE 보유 (anon 137 · authenticated 165 는
--     마이그레이션이 의도적으로 선별 revoke 한 결과이므로 여기서 건드리지 않는다)

-- pgvector 등 확장이 소유한 함수는 grant 대상이 아니라 "no privileges were granted"
-- WARNING 이 100줄 넘게 쏟아진다. 의미 없는 노이즈라 억제한다(에러는 그대로 보인다).
set client_min_messages = error;

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;
grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

-- 프로덕션 예외: 클럽 문의는 조회만 열고 쓰기는 서버(Edge) 경로로만 한다.
revoke insert, update, delete on public.club_inquiry_threads, public.club_inquiry_messages
  from anon, authenticated;

-- 트리거·내부 함수는 마이그레이션이 public/anon/authenticated 에서 revoke 한다.
-- 그 revoke 는 PUBLIC 기본권한도 함께 걷어내므로, 명시 grant 가 없는 클린 재생에서는
-- service_role 까지 실행권한을 잃는다(007 이 잡아내는 상태). 프로덕션과 동일하게 복원한다.
-- anon/authenticated 에는 부여하지 않는다 — 여기에 부여하면 의도적 제한이 깨진다.
grant execute on all functions in schema public to service_role;
