-- 랭킹 본인 연결 — 이의신청 사유 메모
--
-- 배경: 이미 다른 사람과 confirmed 된 선수를 두고 "그거 나다"라고 다투는 경로를
-- 앱에 연다. INSERT 자체는 이미 열려 있다 — org_player_links_claim 정책은 대상
-- 선수가 남과 확정됐는지를 보지 않고(20260805010000 주석 참조), confirmed 1:1 은
-- org_player_links_confirmed_player_key 가 승인 시점에 강제한다. 그래서 이 파일이
-- 하는 일은 관리자가 두 신청자를 가릴 수 있게 사유 한 칸을 붙이는 것뿐이다.
--
-- 왜 사유가 필요한가: 정책이 users.name = org_rankings.player_name 을 요구하므로
-- 경합하는 두 사람의 이름은 반드시 같다. 이름으로는 못 가린다. 랭킹표의 클럽명과
-- 신청자가 적은 소속·연락처를 관리자가 대조하는 것이 유일한 판단 재료다.

begin;

alter table public.org_player_links
  add column if not exists note text;

-- 자유 서술이지만 무제한은 아니다. 두 가지를 따로 잰다:
--   상한은 저장되는 원문 길이로 — btrim 결과만 재면 공백 100만 자 + 'x' 가 통과해
--   길이 1 로 계산된다(btrim 기본은 공백 하나만 지운다).
--   하한은 다듬은 뒤로 — 공백·탭·줄바꿈만 적은 값은 없는 것과 같다.
alter table public.org_player_links
  drop constraint if exists org_player_links_note_len;
alter table public.org_player_links
  add constraint org_player_links_note_len
  check (
    note is null
    or (char_length(note) <= 300
        and char_length(btrim(note, E' \t\n\r')) >= 1)
  );

comment on column public.org_player_links.note is
  '신청·이의신청 사유(소속·연락처 등). pending 동안만 존재한다 — 승인·반려 시 트리거가 지운다.';

-- ── 결정되는 순간 사유를 지운다 ──────────────────────────────────────
-- org_player_links_read 는 confirmed 행을 "모든 로그인 사용자"에게 준다
-- (랭킹 화면의 앱 유저 배지용). RLS 는 행 단위라 note 컬럼만 가릴 수 없으므로,
-- 공개 대상이 되기 전에 값을 비운다. pending 행은 본인과 관리자만 읽는다.
--
-- 이 테이블 전용 트리거라 NEW.note 를 직접 만진다(공유 함수가 아니다).
create or replace function public.clear_org_player_link_note_on_decision()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.status is distinct from 'pending' then
    new.note := null;
  end if;
  return new;
end;
$$;

comment on function public.clear_org_player_link_note_on_decision is
  '승인·반려된 연결의 사유 메모를 비운다. confirmed 행은 전체 공개라 사유가 남으면 새어나간다.';

-- 트리거 전용 함수는 클라이언트 롤에서 실행 권한을 회수한다(011·021 이 지키는 규칙).
-- 트리거 발동에는 호출자의 EXECUTE 가 필요 없다 — 권한 검사는 CREATE TRIGGER 시점 1회다.
-- service_role 은 PUBLIC 기본 실행권한에 기대고 있어 revoke 하면 함께 사라진다.
revoke all on function public.clear_org_player_link_note_on_decision()
  from public, anon, authenticated;
grant execute on function public.clear_org_player_link_note_on_decision()
  to service_role;

drop trigger if exists org_player_links_clear_note on public.org_player_links;
create trigger org_player_links_clear_note
  before insert or update on public.org_player_links
  for each row
  execute function public.clear_org_player_link_note_on_decision();

commit;
