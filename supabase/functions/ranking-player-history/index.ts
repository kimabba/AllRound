import { requireUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import {
  dedupeHistoryRows,
  fetchPlayerHistory,
} from '../_shared/crawler/parsers/gnuboard_player_history.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { parsePlayerHistoryParams } from './validation.ts';

const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

interface CachedFetch {
  fetched_at: string;
  result_count: number;
  is_complete: boolean;
}

Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  const params = parsePlayerHistoryParams(new URL(req.url));
  if (!params) return errorResponse('org 또는 player_id가 올바르지 않습니다', 400);

  const svc = serviceClient();
  const denied = await checkRateLimit(svc, auth.user.id, {
    bucket: 'ranking-player-history',
    maxPerWindow: 30,
    windowSeconds: 60,
  });
  if (denied) return denied;

  const { data: player, error: playerError } = await svc
    .from('org_rankings')
    .select('org_code, org_player_id')
    .eq('org_code', params.orgCode)
    .eq('org_player_id', params.orgPlayerId)
    .limit(1)
    .maybeSingle();
  if (playerError) return errorResponse('선수 정보를 확인하지 못했습니다', 500);
  if (!player) return errorResponse('현재 랭킹에서 선수를 찾을 수 없습니다', 404);

  const { data: cached, error: cacheError } = await svc
    .from('org_player_history_fetches')
    .select('fetched_at, result_count, is_complete')
    .eq('org_code', params.orgCode)
    .eq('org_player_id', params.orgPlayerId)
    .maybeSingle<CachedFetch>();
  if (cacheError) return errorResponse('선수 이력 캐시를 확인하지 못했습니다', 500);

  const fetchedAt = cached?.fetched_at;
  const cacheFresh = fetchedAt != null &&
    Date.now() - new Date(fetchedAt).getTime() < CACHE_TTL_MS;

  if (cacheFresh) {
    const { data, error } = await svc
      .from('org_player_results')
      .select(
        'org_code, org_player_id, tournament_name, played_on, event_raw, result_raw, result_round, points',
      )
      .eq('org_code', params.orgCode)
      .eq('org_player_id', params.orgPlayerId)
      .order('played_on', { ascending: false });
    if (error) return errorResponse('선수 이력을 불러오지 못했습니다', 500);
    return jsonResponse({
      results: data ?? [],
      fetched_at: fetchedAt,
      cached: true,
      is_complete: cached?.is_complete ?? true,
    });
  }

  const { data: source, error: sourceError } = await svc
    .from('crawl_sources')
    .select('url')
    .eq('org_code', params.orgCode)
    .eq('parser_module', 'gnuboard-ranking')
    .eq('enabled', true)
    .limit(1)
    .maybeSingle();
  if (sourceError || !source || typeof source.url !== 'string') {
    return errorResponse('협회 이력 출처를 찾지 못했습니다', 503);
  }

  try {
    const fetched = await fetchPlayerHistory(source.url, params.orgPlayerId);
    // 크롤러(crawlPlayerHistories)와 같은 RPC·같은 dedupe를 쓴다 — 별도 경로를
    // 만들면 크롤러가 이미 겪은 "같은 대회명+날짜 중복 → ON CONFLICT 이중 처리로
    // 문장 전체 롤백" 사고를 여기서 다시 밟는다(2026-08-19 실측, #468).
    const rows = dedupeHistoryRows(fetched.rows);
    const { error: upsertError } = await svc.rpc('upsert_org_player_results', {
      p_org: params.orgCode,
      p_org_player_id: params.orgPlayerId,
      p_rows: rows.map((row) => ({
        tournament_name: row.tournamentName,
        played_on: row.playedOn,
        event_raw: row.eventRaw,
        result_raw: row.resultRaw,
        result_round: row.resultRound,
        points: row.points,
      })),
    });
    if (upsertError) {
      console.error('[ranking-player-history] upsert failed:', upsertError.message);
      return errorResponse('선수 이력을 저장하지 못했습니다', 500);
    }

    const fetchedAtIso = new Date().toISOString();
    // 캐시 시각 기록은 결과 저장 성공 뒤에만 한다. 이게 실패해도 무해하다 —
    // 다음 탭에서 캐시가 없으니 한 번 더 긁을 뿐, 데이터가 틀리게 남지 않는다.
    const { error: stampError } = await svc.from('org_player_history_fetches').upsert({
      org_code: params.orgCode,
      org_player_id: params.orgPlayerId,
      fetched_at: fetchedAtIso,
      result_count: rows.length,
      is_complete: !fetched.reachedPageLimit,
    });
    if (stampError) {
      console.error('[ranking-player-history] cache stamp failed:', stampError.message);
    }

    return jsonResponse({
      results: rows.map((row) => ({
        org_code: params.orgCode,
        org_player_id: params.orgPlayerId,
        tournament_name: row.tournamentName,
        played_on: row.playedOn,
        event_raw: row.eventRaw,
        result_raw: row.resultRaw,
        result_round: row.resultRound,
        points: row.points,
      })),
      fetched_at: fetchedAtIso,
      cached: false,
      is_complete: !fetched.reachedPageLimit,
    });
  } catch (error) {
    console.error(
      '[ranking-player-history] source fetch failed:',
      error instanceof Error ? error.message : String(error),
    );
    return errorResponse(
      '협회에서 선수 이력을 가져오지 못했습니다. 잠시 후 다시 시도해주세요.',
      502,
    );
  }
}));
