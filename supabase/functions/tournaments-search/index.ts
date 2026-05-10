import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { isValidRegionCode, isValidTennisOrg } from '../_shared/enums.ts';

/**
 * GET /tournaments-search
 *  ?sport=tennis|futsal
 *  &region=광주
 *  &date_from=2026-05-01
 *  &date_to=2026-12-31
 *  &only_my_grade=true|false   (default: true — D 핵심 자동 필터링)
 *  &q=검색어
 *  &limit=50
 *  &offset=0
 *
 * 사용자 등급 기반 자동 필터링:
 *  user_sports 와 tournaments.eligible_grades 를 종목별로 매칭한다.
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
  const region = url.searchParams.get('region');           // 자유 텍스트 (구 컬럼)
  const regionCode = url.searchParams.get('region_code');  // 권역 (gwangju, seoul_metro 등)
  if (regionCode && !isValidRegionCode(regionCode)) {
    return errorResponse('invalid region_code');
  }
  const org = url.searchParams.get('org');                 // 협회 (kta, kato 등)
  if (org && !isValidTennisOrg(org)) {
    return errorResponse('invalid org');
  }
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const onlyMyGrade = url.searchParams.get('only_my_grade') !== 'false';
  const q = url.searchParams.get('q');
  if (q && q.length > 200) {
    return errorResponse('q too long (max 200 chars)');
  }
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') ?? '50', 10), 1), 100);
  const offset = Math.max(parseInt(url.searchParams.get('offset') ?? '0', 10), 0);

  const { supabase, user } = auth;
  const { data, error } = await supabase.rpc('tournaments_for_user', {
    p_user_id: user.id,
    p_sport: sport,
    p_region: region,
    p_date_from: dateFrom,
    p_date_to: dateTo,
    p_only_my_grade: onlyMyGrade,
    p_query: q,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) return errorResponse(error.message, 500);

  // region_code · org 는 RPC 시그니처가 아직 받지 않아 client-side 필터.
  // 향후 RPC v2로 시그니처 확장 시 여기 제거.
  const rawRows: unknown[] = Array.isArray(data) ? data : [];
  const filtered = rawRows.filter((row): boolean => {
    if (typeof row !== 'object' || row === null) return false;
    const o = row as Record<string, unknown>;
    if (regionCode && o.region_code !== regionCode) return false;
    if (org) {
      const hostOrgs = Array.isArray(o.host_orgs) ? o.host_orgs : [];
      if (!hostOrgs.includes(org)) return false;
    }
    return true;
  });

  return jsonResponse({ tournaments: filtered, limit, offset });
});
