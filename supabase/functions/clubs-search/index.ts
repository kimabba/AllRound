import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { boundingBox, distanceKm, numberParam } from './nearby.ts';

/**
 * GET /clubs-search?sport=tennis&region=광주&q=...
 */
Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  const url = new URL(req.url);
  const sport = url.searchParams.get('sport');
  if (sport && sport !== 'tennis' && sport !== 'futsal') {
    return errorResponse('sport must be tennis or futsal');
  }
  const region = url.searchParams.get('region');
  const latitude = numberParam(url.searchParams.get('latitude'));
  const longitude = numberParam(url.searchParams.get('longitude'));
  const radiusKm = numberParam(url.searchParams.get('radius_km'));
  const nearbyRequested = latitude !== null || longitude !== null || radiusKm !== null;
  if (
    nearbyRequested &&
    (latitude === null || longitude === null || radiusKm === null ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 ||
      radiusKm < 1 || radiusKm > 50)
  ) {
    return errorResponse('invalid nearby search coordinates or radius', 400);
  }
  const rawQ = url.searchParams.get('q');
  // PostgREST .or() 표현식 메타문자 제거 (SEC-M-01 방어)
  const q = rawQ?.replace(/[(),:%_]/g, ' ').trim().slice(0, 100);
  const limit = Math.min(
    Math.max(parseInt(url.searchParams.get('limit') ?? '50', 10), 1),
    200,
  );

  // mine=true 이면 본인이 생성했거나 멤버인 클럽 (pending 포함)
  const mine = url.searchParams.get('mine') === 'true';

  if (mine) {
    const supa = serviceClient();
    // 1) 본인이 active 멤버인 클럽+역할 조회
    const { data: memberRows } = await supa
      .from('club_members')
      .select('club_id, role, status, can_post_notice')
      .eq('user_id', auth.user.id)
      .eq('status', 'active');
    const memberMap = new Map(
      (memberRows ?? []).map((
        r: {
          club_id: string;
          role: string;
          status: string;
          can_post_notice: boolean;
        },
      ) => [
        r.club_id,
        {
          role: r.role,
          status: r.status,
          can_post_notice: r.can_post_notice,
        },
      ]),
    );
    const memberClubIds = [...memberMap.keys()];

    // 2) 멤버이거나 생성자인 클럽 조회
    let clubQuery = supa.from('clubs').select('*');
    if (memberClubIds.length > 0) {
      clubQuery = clubQuery.or(
        `created_by.eq.${auth.user.id},id.in.(${memberClubIds.join(',')})`,
      );
    } else {
      clubQuery = clubQuery.eq('created_by', auth.user.id);
    }
    const { data, error } = await clubQuery.order('name', { ascending: true });
    if (error) return errorResponse(error.message, 500);

    // 3) club_members 필드를 직접 주입
    const clubs = (data ?? []).map((c: Record<string, unknown>) => {
      const mem = memberMap.get(c['id'] as string);
      return {
        ...c,
        club_members: mem ? [{ ...mem, user_id: auth.user.id }] : [],
      };
    });
    return jsonResponse({ clubs });
  }

  if (latitude !== null && longitude !== null && radiusKm !== null) {
    const supa = serviceClient();
    // 반경을 감싸는 사각형으로 DB 에서 먼저 좁힌다. 이게 없으면 정렬 없는
    // limit(500) 이 반경 밖 클럽으로 먼저 채워져 실제 근거리 클럽이 빠진다.
    const box = boundingBox(latitude, longitude, radiusKm);
    let nearbyQuery = supa
      .from('clubs')
      .select('*')
      .eq('status', 'approved')
      .not('latitude', 'is', null)
      .not('longitude', 'is', null)
      .gte('latitude', box.minLatitude)
      .lte('latitude', box.maxLatitude)
      .gte('longitude', box.minLongitude)
      .lte('longitude', box.maxLongitude)
      // 사각형 안이 500개를 넘길 만큼 조밀해지면 반경 질의를 PostGIS 로 옮긴다.
      .limit(500);
    if (sport) nearbyQuery = nearbyQuery.eq('sport', sport);
    const { data, error } = await nearbyQuery;
    if (error) return errorResponse(error.message, 500);

    const { data: memberships } = await supa
      .from('club_members')
      .select('club_id, role, status, can_post_notice')
      .eq('user_id', auth.user.id)
      .eq('status', 'active');
    const membershipByClub = new Map(
      (memberships ?? []).map((membership) => [
        membership.club_id as string,
        membership,
      ]),
    );

    const clubs = (data ?? [])
      .map((club) => {
        const clubLatitude = club.latitude as number | null;
        const clubLongitude = club.longitude as number | null;
        if (clubLatitude === null || clubLongitude === null) return null;
        const distance = distanceKm(
          latitude,
          longitude,
          clubLatitude,
          clubLongitude,
        );
        if (distance > radiusKm) return null;
        const membership = membershipByClub.get(club.id as string);
        return {
          ...club,
          distance_km: Math.round(distance * 10) / 10,
          club_members: membership ? [{ ...membership, user_id: auth.user.id }] : [],
        };
      })
      .filter((club): club is Record<string, unknown> => club !== null)
      .sort((a, b) => (a.distance_km as number) - (b.distance_km as number))
      .slice(0, limit);
    return jsonResponse({ clubs });
  }

  // 일반 검색: approved 클럽만
  // club_members 는 요청자 본인 것만 임베드한다. 필터하지 않으면 전체 멤버가
  // 반환되고 Club.fromJson 이 members.first(=owner)를 내 역할로 오인해, 비오너도
  // 클럽장으로 표시되고 관리 탭이 노출된다(getClub 과 동일하게 user_id 로 필터).
  let query = auth.supabase
    .from('clubs')
    .select(
      '*, meeting_days, monthly_fee, gender_preference, club_members!left(role, status, can_post_notice)',
    )
    .eq('status', 'approved')
    .eq('club_members.user_id', auth.user.id)
    .limit(limit);

  if (sport) query = query.eq('sport', sport);
  // clubs.region 표기 혼재("광주"/"광주광역시")·region_code 컬럼 없음 → 부분일치(JY-104).
  if (region) query = query.ilike('region', `%${region}%`);
  if (q) query = query.or(`name.ilike.%${q}%,description.ilike.%${q}%`);

  const { data, error } = await query.order('name', { ascending: true });
  if (error) return errorResponse(error.message, 500);
  return jsonResponse({ clubs: data ?? [] });
});
