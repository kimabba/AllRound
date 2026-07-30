import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { assertKnownOrgs } from '../_shared/orgs.ts';
import { isValidRegionCode, parseDivisionCodes, parseRecruiting } from '../_shared/enums.ts';

/**
 * GET /tournaments-search
 *  ?sport=tennis|futsal
 *  &region=광주
 *  &date_from=2026-05-01
 *  &date_to=2026-12-31
 *  &only_my_grade=true|false   (default: true — D 핵심 자동 필터링)
 *  &q=검색어
 *  &division_codes=gj_m_gold,jn_m_gold   (쉼표구분 부서 코드 — 협회 무관, eligible_grades 와 겹침 매칭)
 *  &recruiting=open|closed   (모집상태 — application_deadline 기준; 그 외 값은 무시)
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
  const { supabase, user } = auth;

  const url = new URL(req.url);
  const sport = url.searchParams.get('sport');
  if (sport && sport !== 'tennis' && sport !== 'futsal') {
    return errorResponse('sport must be tennis or futsal');
  }
  const region = url.searchParams.get('region'); // 자유 텍스트 (구 컬럼)
  const regionCode = url.searchParams.get('region_code'); // 권역 (gwangju, seoul_metro 등)
  if (regionCode && !isValidRegionCode(regionCode)) {
    return errorResponse('invalid region_code');
  }
  const org = url.searchParams.get('org'); // 협회 (kta, kato 등)
  if (org) {
    // 협회 정본은 DB tennis_orgs 다(JY-135, #330). 정적 목록으로 검증하면 새 협회로
    // 필터를 눌러도 "invalid org" 로 거절된다 — 0건 결과가 아니라 검증 실패였다.
    const orgError = await assertKnownOrgs(supabase, [org]);
    if (orgError) return errorResponse(orgError.message, orgError.status);
  }
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const onlyMyGrade = url.searchParams.get('only_my_grade') !== 'false';
  const q = url.searchParams.get('q');
  if (q && q.length > 200) {
    return errorResponse('q too long (max 200 chars)');
  }
  // 쉼표구분 부서 코드 → 형식 sanitize 후 배열(빈값이면 null = 필터 미적용).
  const divisionCodes = parseDivisionCodes(url.searchParams.get('division_codes'));
  // 모집상태 → 'open'|'closed' 만 통과, 그 외(빈값/오타)는 null = 필터 미적용.
  const recruiting = parseRecruiting(url.searchParams.get('recruiting'));
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') ?? '50', 10), 1), 100);
  const offset = Math.max(parseInt(url.searchParams.get('offset') ?? '0', 10), 0);

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
    p_region_code: regionCode,
    p_host_org: org,
    p_division_codes: divisionCodes,
    p_recruiting: recruiting,
  });

  if (error) return errorResponse(error.message, 500);

  return jsonResponse({ tournaments: Array.isArray(data) ? data : [], limit, offset });
});
