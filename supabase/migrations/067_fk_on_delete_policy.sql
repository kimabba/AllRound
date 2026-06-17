-- 067: FK ON DELETE 정책 정합 (P1, 코덱스 교차검증)
--
-- 문제: 8개 FK 가 ON DELETE NO ACTION 이라
--   - 사용자(auth.users/public.users) 삭제가 이 행들 때문에 막히거나
--   - 의미상 부적절(작성자/검토자/상대/파트너가 삭제돼도 본문은 남아야 함).
--
-- 정책:
--   - club_event_attendees.user_id : CASCADE (참석 응답은 사용자와 함께 삭제)
--   - club_events.created_by        : SET NULL (이벤트는 클럽 소유, 작성자만 비움 → nullable 화)
--   - club_join_requests.reviewed_by: SET NULL (검토 이력 유지)
--   - clubs.approved_by             : SET NULL (승인자 삭제돼도 클럽 유지)
--   - match_entries.partner_id      : SET NULL (파트너 삭제돼도 내 전적 유지)
--   - match_rounds.opponent_1/2_id  : SET NULL (상대 삭제돼도 라운드 유지)
--
-- target(auth.users vs public.users) 통일은 데이터 정합 검증이 필요한 별도 작업으로 보류.
-- 데이터가 거의 없는 시점이라 FK 재생성 락 위험은 무시 가능.

begin;

alter table public.club_event_attendees drop constraint club_event_attendees_user_id_fkey;
alter table public.club_event_attendees
  add constraint club_event_attendees_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.club_events alter column created_by drop not null;
alter table public.club_events drop constraint club_events_created_by_fkey;
alter table public.club_events
  add constraint club_events_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.club_join_requests drop constraint club_join_requests_reviewed_by_fkey;
alter table public.club_join_requests
  add constraint club_join_requests_reviewed_by_fkey
  foreign key (reviewed_by) references auth.users(id) on delete set null;

alter table public.clubs drop constraint clubs_approved_by_fkey;
alter table public.clubs
  add constraint clubs_approved_by_fkey
  foreign key (approved_by) references auth.users(id) on delete set null;

alter table public.match_entries drop constraint match_entries_partner_id_fkey;
alter table public.match_entries
  add constraint match_entries_partner_id_fkey
  foreign key (partner_id) references public.users(id) on delete set null;

alter table public.match_rounds drop constraint match_rounds_opponent_1_id_fkey;
alter table public.match_rounds
  add constraint match_rounds_opponent_1_id_fkey
  foreign key (opponent_1_id) references public.users(id) on delete set null;

alter table public.match_rounds drop constraint match_rounds_opponent_2_id_fkey;
alter table public.match_rounds
  add constraint match_rounds_opponent_2_id_fkey
  foreign key (opponent_2_id) references public.users(id) on delete set null;

commit;
