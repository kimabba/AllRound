-- 랭킹 본인 연결 — 신청·승인·반려 알림
--
-- 왜 트리거인가: 랭킹 신청은 Edge Function 을 거치지 않는다. 앱이 PostgREST 로
-- org_player_links 에 직접 INSERT 한다(claimRanking). 클럽 승인 알림은
-- clubs-create Edge 가 만들지만 여기는 그럴 자리가 없어 DB 가 유일한 훅이다.
--
-- 연결 해제도 confirmed → rejected 라 같은 규칙에 걸린다 — 해제당한 사람이
-- 아무 통보 없이 개인 기록장을 잃던 문제가 이걸로 함께 덮인다.
--
-- 푸시(FCM)는 안 간다. 발송은 Edge 의 createNotification() 이 직접 하고
-- notify-cron 은 대회 후보만 다시 훑는다. 트리거로 넣은 행은 앱 알림함(뱃지)
-- 까지만 간다 — 신청 빈도가 월 몇 건 수준이라 의도적으로 여기서 멈춘다.
-- ponytail: pending 알림을 밀어내는 범용 워커가 생기면 자동으로 푸시된다.

begin;

alter table public.notifications
  drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check check (type in (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request', 'club_inquiry_received', 'club_inquiry_reply',
    'club_dues_reminder', 'club_chat_message',
    'ranking_claim_request', 'ranking_claim_approved', 'ranking_claim_rejected'
  ));

-- ── 신청이 들어오면 관리자 전원에게 ──────────────────────────────────
--
-- security definer 인 이유: notifications 의 INSERT 정책은 is_admin() 뿐이다.
-- 신청자는 일반 사용자라, invoker 로 두면 자기 신청 알림을 만들지 못한다.
create or replace function public.notify_ranking_claim_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid;
  v_player_name text;
  v_is_dispute boolean;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  -- 선수명은 미러에서 가져온다. 크롤이 부서를 갈아엎는 사이면 못 찾을 수 있어
  -- (org_player_links 는 FK 없이 텍스트 id 로만 참조한다) 폴백을 둔다.
  select r.player_name into v_player_name
  from public.org_rankings r
  where r.org_code = new.org_code and r.org_player_id = new.org_player_id
  limit 1;

  -- 이미 남이 확정한 선수면 이의신청이다 — 관리자가 목록에서 바로 알아야 한다.
  select exists (
    select 1 from public.org_player_links other
    where other.org_code = new.org_code
      and other.org_player_id = new.org_player_id
      and other.user_id <> new.user_id
      and other.status = 'confirmed'
  ) into v_is_dispute;

  for v_admin in select id from public.users where role = 'admin'
  loop
    insert into public.notifications (
      user_id, type, title, body, reference_type, reference_id
    ) values (
      v_admin,
      'ranking_claim_request',
      case when v_is_dispute then '랭킹 연결 이의신청' else '랭킹 본인 연결 신청' end,
      format(
        '%s 선수에 %s이 들어왔습니다.',
        coalesce(v_player_name, '(이름 확인 필요)'),
        case when v_is_dispute then '이의신청' else '연결 신청' end
      ),
      -- reference_type 이 앱의 딥링크 분기다(NotificationEvent 에 type 이 없다).
      -- 관리자용과 신청자용을 다른 값으로 둬야 각각 다른 화면으로 간다.
      'ranking_claim_request',
      new.id
    ) on conflict do nothing;
  end loop;
  return new;
end;
$$;

comment on function public.notify_ranking_claim_request is
  '본인 연결 신청(pending)이 들어오면 관리자 전원 알림함에 넣는다. 앱이 PostgREST 직행이라 Edge 훅이 없다.';

-- ── 결정되면 신청자에게 ──────────────────────────────────────────────
create or replace function public.notify_ranking_claim_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player_name text;
begin
  -- 상태가 실제로 바뀐 경우만. 관리자가 decided_by 만 다시 쓰는 갱신에는
  -- 알림이 나가면 안 된다.
  if new.status is not distinct from old.status
     or new.status = 'pending' then
    return new;
  end if;

  select r.player_name into v_player_name
  from public.org_rankings r
  where r.org_code = new.org_code and r.org_player_id = new.org_player_id
  limit 1;

  insert into public.notifications (
    user_id, type, title, body, reference_type, reference_id
  ) values (
    new.user_id,
    case when new.status = 'confirmed'
      then 'ranking_claim_approved' else 'ranking_claim_rejected' end,
    case when new.status = 'confirmed'
      then '랭킹 본인 연결 완료' else '랭킹 본인 연결 해제' end,
    case when new.status = 'confirmed'
      then format('%s 선수와 연결됐습니다. 개인 기록장에서 전적을 볼 수 있어요.',
                  coalesce(v_player_name, '해당'))
      -- confirmed → rejected(관리자 해제)와 pending → rejected(반려)를 한 문구로
      -- 덮는다. 받는 사람 입장에서 결과는 같다 — 연결이 없다.
      else format('%s 선수 연결이 해제되었습니다. 문의는 관리자에게 남겨주세요.',
                  coalesce(v_player_name, '해당'))
    end,
    -- 신청자용 — /rankings/me(개인 기록장)로 보낸다.
    'ranking_claim_result',
    new.id
  ) on conflict do nothing;
  return new;
end;
$$;

comment on function public.notify_ranking_claim_decision is
  '승인·반려·연결해제를 신청자에게 알린다. 해제(confirmed→rejected)도 같은 경로로 통보된다.';

drop trigger if exists org_player_links_notify_request on public.org_player_links;
create trigger org_player_links_notify_request
  after insert on public.org_player_links
  for each row
  execute function public.notify_ranking_claim_request();

drop trigger if exists org_player_links_notify_decision on public.org_player_links;
create trigger org_player_links_notify_decision
  after update of status on public.org_player_links
  for each row
  execute function public.notify_ranking_claim_decision();

-- 트리거 전용 함수는 클라이언트 롤에서 회수한다(011·021 규칙).
revoke all on function public.notify_ranking_claim_request() from public, anon, authenticated;
grant execute on function public.notify_ranking_claim_request() to service_role;
revoke all on function public.notify_ranking_claim_decision() from public, anon, authenticated;
grant execute on function public.notify_ranking_claim_decision() to service_role;

commit;
