-- 온보딩이 지역을 users.primary_region 에 저장하지 않아(협회 등록 시에만
-- user_tennis_orgs.region_code 에 실림) 지역이 유실되던 버그의 데이터 정정.
--
-- 앱 수정: 온보딩이 항상 users.primary_region 을 쓰고, user_tennis_orgs.region_code
-- 는 더 이상 쓰지 않는다(유저 지역의 단일 진실원천 = users.primary_region).
-- 여기서는 기존 협회 등록자의 지역을 primary_region 으로 옮긴다.

BEGIN;

-- 17시도 정본(regions.is_active)에 있는 코드만 백필한다.
-- deprecated 묶음 코드(seoul_metro / chungcheong 등)는 시도 단위로 특정할 수
-- 없으므로 옮기지 않고 사용자가 온보딩에서 다시 고르게 둔다.
UPDATE public.users u
SET primary_region = src.region_code
FROM (
  SELECT DISTINCT ON (uto.user_id) uto.user_id, uto.region_code
  FROM public.user_tennis_orgs uto
  JOIN public.regions r ON r.code = uto.region_code AND r.is_active
  ORDER BY uto.user_id, uto.is_primary DESC, uto.updated_at DESC
) src
WHERE u.id = src.user_id
  AND u.primary_region IS NULL;

COMMENT ON COLUMN public.user_tennis_orgs.region_code IS
  'DEPRECATED — 유저 활동 지역은 users.primary_region 단일 소스. 앱은 쓰지 않는다.';

COMMIT;
