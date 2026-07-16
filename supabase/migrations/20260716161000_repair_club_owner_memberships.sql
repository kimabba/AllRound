-- 승인·심사 중인 클럽의 개설자는 owner active 멤버여야 한다.
-- 과거 테스트/운영 흐름에서 누락되거나 left로 남은 owner 행만 복구한다.
INSERT INTO public.club_members (club_id, user_id, role, status, left_at)
SELECT club.id, club.created_by, 'owner', 'active', NULL
FROM public.clubs AS club
WHERE club.created_by IS NOT NULL
  AND club.status IN ('pending', 'approved')
  AND club.status_reason IS DISTINCT FROM 'deleted_by_owner'
ON CONFLICT (club_id, user_id) DO UPDATE
SET
  status = 'active',
  left_at = NULL,
  role = 'owner';
