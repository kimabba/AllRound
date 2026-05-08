import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';

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
  const region = url.searchParams.get('region');
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
  return jsonResponse({ tournaments: data ?? [], limit, offset });
});
