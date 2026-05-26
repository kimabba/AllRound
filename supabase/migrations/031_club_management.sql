-- Migration 031: Club management — status workflow, members, join requests
-- Applied directly in previous session; this file documents the schema.

-- 1. clubs 테이블 확장: 승인 워크플로우 컬럼
ALTER TABLE clubs
  ADD COLUMN IF NOT EXISTS status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  ADD COLUMN IF NOT EXISTS status_reason text,
  ADD COLUMN IF NOT EXISTS approved_by   uuid REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS approved_at   timestamptz,
  ADD COLUMN IF NOT EXISTS member_count  int  NOT NULL DEFAULT 0;

-- 기존 active=true 클럽은 approved로, false는 rejected로 마이그레이션
UPDATE clubs SET status = CASE WHEN active THEN 'approved' ELSE 'rejected' END
  WHERE status = 'pending';

-- 2. club_members 테이블
CREATE TABLE IF NOT EXISTS club_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id    uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       text NOT NULL DEFAULT 'member' CHECK (role IN ('owner','manager','member')),
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','left','banned')),
  joined_at  timestamptz NOT NULL DEFAULT now(),
  left_at    timestamptz,
  UNIQUE (club_id, user_id)
);

CREATE INDEX IF NOT EXISTS club_members_club_id_idx ON club_members(club_id);
CREATE INDEX IF NOT EXISTS club_members_user_id_idx ON club_members(user_id);

-- 3. club_join_requests 테이블
CREATE TABLE IF NOT EXISTS club_join_requests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id     uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message     text,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by uuid REFERENCES users(id),
  reviewed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, user_id)
);

CREATE INDEX IF NOT EXISTS club_join_requests_club_id_idx ON club_join_requests(club_id);
CREATE INDEX IF NOT EXISTS club_join_requests_user_id_idx ON club_join_requests(user_id);

-- 4. RLS 정책
ALTER TABLE club_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE club_join_requests ENABLE ROW LEVEL SECURITY;

-- club_members: 본인 멤버십은 볼 수 있고, 같은 클럽 멤버도 볼 수 있음
CREATE POLICY club_members_select ON club_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR club_id IN (
      SELECT club_id FROM club_members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- club_join_requests: 본인 신청과 클럽 owner/manager만 볼 수 있음
CREATE POLICY club_join_requests_select ON club_join_requests
  FOR SELECT USING (
    user_id = auth.uid()
    OR club_id IN (
      SELECT club_id FROM club_members
      WHERE user_id = auth.uid() AND status = 'active' AND role IN ('owner','manager')
    )
  );

-- 5. member_count 자동 갱신 트리거
CREATE OR REPLACE FUNCTION update_club_member_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE clubs SET member_count = (
    SELECT COUNT(*) FROM club_members WHERE club_id = COALESCE(NEW.club_id, OLD.club_id) AND status = 'active'
  ) WHERE id = COALESCE(NEW.club_id, OLD.club_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS club_members_count_trigger ON club_members;
CREATE TRIGGER club_members_count_trigger
  AFTER INSERT OR UPDATE OR DELETE ON club_members
  FOR EACH ROW EXECUTE FUNCTION update_club_member_count();
