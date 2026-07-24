import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireEligibleMember } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { embedText, toVectorLiteral } from '../_shared/embedding.ts';
import { Sport } from '../_shared/enums.ts';

/**
 * POST /semantic-search
 * Body: {
 *   query: string,
 *   target?: 'tournaments' | 'rules' | 'both' (default: both),
 *   sport?: 'tennis' | 'futsal',
 *   only_my_grade?: boolean (default: true)  — tournaments 에만 적용
 *   match_count?: number  (default: 10 for tournaments, 5 for rules)
 * }
 *
 * Gemini 임베딩 → pgvector 유사도 검색 → DB 결과 반환.
 * chat 함수에서 RAG 컨텍스트 수집용으로도 호출.
 */
interface Body {
  query: string;
  target?: 'tournaments' | 'rules' | 'both';
  sport?: Sport;
  only_my_grade?: boolean;
  match_count?: number;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireEligibleMember(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  // Rate limit: 10 req/min per user.
  // chat_rate_limit 은 service_role 전용 RLS(065) → user client 접근 시 fail-open.
  // service_role RPC 로 통일.
  const denied = await checkRateLimit(serviceClient(), user.id, {
    bucket: 'semantic-search',
    maxPerWindow: 10,
    windowSeconds: 60,
  });
  if (denied) return denied;

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.query?.trim()) return errorResponse('query required');

  const target = body.target ?? 'both';
  const matchCount = Math.min(Math.max(body.match_count ?? 10, 1), 30);

  let queryEmbedding: number[];
  try {
    queryEmbedding = await embedText(body.query, 'RETRIEVAL_QUERY');
  } catch (e) {
    return errorResponse(`Embedding failed: ${(e as Error).message}`, 500);
  }
  const literal = toVectorLiteral(queryEmbedding);

  type RpcResult = { data: unknown; error: { message: string } | null };

  const tournamentsPromise: Promise<RpcResult | null> =
    (target === 'tournaments' || target === 'both')
      ? Promise.resolve(
        supabase.rpc('tournaments_semantic_search', {
          p_user_id: user.id,
          p_query_embedding: literal,
          p_only_my_grade: body.only_my_grade ?? true,
          p_match_count: matchCount,
        }),
      ) as Promise<RpcResult>
      : Promise.resolve(null);

  const rulesPromise: Promise<RpcResult | null> = (target === 'rules' || target === 'both')
    ? Promise.resolve(
      supabase.rpc('rules_semantic_search', {
        p_query_embedding: literal,
        p_sport: body.sport ?? null,
        p_match_count: Math.min(matchCount, 10),
      }),
    ) as Promise<RpcResult>
    : Promise.resolve(null);

  const [tournamentsResult, rulesResult] = await Promise.all([
    tournamentsPromise,
    rulesPromise,
  ]);

  if (tournamentsResult?.error) return errorResponse(tournamentsResult.error.message, 500);
  if (rulesResult?.error) return errorResponse(rulesResult.error.message, 500);

  return jsonResponse({
    tournaments: tournamentsResult?.data ?? [],
    rules: rulesResult?.data ?? [],
  });
});
