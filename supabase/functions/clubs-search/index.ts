import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';

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
  const rawQ = url.searchParams.get('q');
  // PostgREST .or() 표현식 메타문자 제거 (SEC-M-01 방어)
  const q = rawQ?.replace(/[(),:%_]/g, ' ').trim().slice(0, 100);
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') ?? '50', 10), 1), 200);

  let query = auth.supabase.from('clubs').select('*').eq('active', true).limit(limit);
  if (sport) query = query.eq('sport', sport);
  if (region) query = query.eq('region', region);
  if (q) query = query.or(`name.ilike.%${q}%,description.ilike.%${q}%`);

  const { data, error } = await query.order('name', { ascending: true });
  if (error) return errorResponse(error.message, 500);
  return jsonResponse({ clubs: data ?? [] });
});
