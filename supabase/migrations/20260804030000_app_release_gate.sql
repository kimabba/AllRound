-- 최소 지원 빌드 게이트 (강제 업데이트)
--
-- 배경: 앱이 App Store 에 올라간 뒤(빌드 5)에도 구버전을 새 버전으로 밀 수단이 없었다.
--   서버·DB 는 계속 바뀌는데, 이미 나간 앱이 깨지면 사용자는 깨진 앱에 갇힌다.
--   실제로 2026-08-04 마이그레이션 3건을 밀 때 앱이 부르는 RPC 와 손으로 대조해서
--   통과시켰다 — 그 대조는 매번 필요하고, 한 번 놓치면 되돌릴 방법이 없다.
--
-- 이 게이트의 한계를 분명히 해둔다: **빌드 5 에는 이 코드가 없다.** 즉 지금 이미 나간
--   버전은 여기서 뭘 하든 막을 수 없다. 효력은 이 코드가 들어간 다음 빌드부터다.
--   그래서 지금 넣어두는 것이고, min_build 를 올려도 지금은 아무도 막히지 않는다.
--
-- 왜 앱이 직접 읽나(Edge 경유가 아니라): 로그인 전에도 판정해야 하고, Edge 가 죽어도
--   게이트 조회 실패로 앱이 막히면 안 된다. 앱은 실패 시 통과(fail-open)한다 —
--   이건 보안 장치가 아니라 UX 장치다. 진짜 강제는 서버 RLS/Edge 가 한다.

begin;

create table public.app_release_gate (
  platform   text primary key check (platform in ('ios', 'android')),
  -- 이 값 **미만**의 빌드는 차단된다. pubspec 의 `+N`(빌드번호)과 같은 축이다.
  -- 빌드번호는 증가만 하고 재사용하지 않으므로 단조 비교가 성립한다.
  min_build  int not null check (min_build >= 1),
  -- 앱 ID 가 확정되기 전에는 NULL 이다. 추측 URL 을 넣지 않는다 —
  -- 앱은 NULL 이면 버튼 대신 "스토어에서 검색" 안내를 보여준다.
  store_url  text,
  -- 왜 올렸는지. 사용자에게 보여주지 않는다(운영 기록).
  note       text,
  updated_at timestamptz not null default now()
);

comment on table public.app_release_gate is
  '플랫폼별 최소 지원 빌드번호. 이 값 미만의 앱은 시작 시 업데이트 안내로 막힌다. 올리는 것은 명시적 운영 결정이다.';

create trigger app_release_gate_touch_updated_at
  before update on public.app_release_gate
  for each row execute function public.touch_updated_at();

alter table public.app_release_gate enable row level security;

-- 로그인 전에도 판정해야 하므로 anon 도 읽는다. 숨길 내용이 없다(공개 최소버전).
-- TO 를 명시한다 — 생략하면 PUBLIC 이 되는 함정(#365)을 피한다.
create policy app_release_gate_read on public.app_release_gate
  for select to anon, authenticated
  using (true);

-- 쓰기는 service_role 전용. 관리자 UI 를 두지 않는다 — 잘못 올리면 전원이 앱을 못 쓰므로
-- 손이 한 번 더 가는 편이 낫다.
grant select on public.app_release_gate to anon, authenticated;
grant all on public.app_release_gate to service_role;

-- 초기값: 게이트는 설치하되 아무도 막지 않는다(현재 빌드 5 > 1).
-- 실제로 막는 것은 이 값을 올리는 순간이고, 그건 별도 결정이다.
insert into public.app_release_gate (platform, min_build, note) values
  ('ios',     1, '게이트 설치 시 기본값 — 아무도 막지 않는다'),
  ('android', 1, '게이트 설치 시 기본값 — 아무도 막지 않는다');

commit;
