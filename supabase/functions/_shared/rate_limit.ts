import { SupabaseClient } from '@supabase/supabase-js';
import { errorResponse } from './cors.ts';

export interface RateLimitConfig {
  bucket: string;          // 'chat' / 'semantic-search' / ...
  maxPerWindow: number;    // 윈도우당 허용 호출 수
  windowSeconds: number;   // 윈도우 길이(초)
}

interface RpcRow {
  allowed: boolean;
  current_count: number;
  reset_at: string;
}

/**
 * fixed-window rate limit 검사 + 카운트 증가.
 *
 * 사용:
 *   const denied = await checkRateLimit(serviceClient(), userId, {
 *     bucket: 'chat', maxPerWindow: 30, windowSeconds: 60,
 *   });
 *   if (denied) return denied;
 *
 * RPC 자체가 실패하면 (DB 장애) **요청은 통과시킨다** — 사용자 경험 우선.
 * 단, 콘솔에 에러 기록.
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  config: RateLimitConfig,
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('consume_rate_limit', {
    p_user_id: userId,
    p_bucket: config.bucket,
    p_max_per_window: config.maxPerWindow,
    p_window_seconds: config.windowSeconds,
  });

  if (error) {
    console.error(`[rate_limit] consume_rate_limit failed for ${config.bucket}:`, error.message);
    return null; // fail-open
  }

  const row: RpcRow | undefined = Array.isArray(data) ? data[0] : data;
  if (!row || row.allowed) return null;

  const resetAt = row.reset_at;
  const retryAfterSec = Math.max(
    1,
    Math.ceil((new Date(resetAt).getTime() - Date.now()) / 1000),
  );
  const res = errorResponse(
    `Rate limit exceeded for ${config.bucket}. ` +
      `최대 ${config.maxPerWindow}회 / ${config.windowSeconds}초. ` +
      `${retryAfterSec}초 후 다시 시도하세요.`,
    429,
    { reset_at: resetAt, limit: config.maxPerWindow, window_seconds: config.windowSeconds },
  );
  res.headers.set('Retry-After', retryAfterSec.toString());
  return res;
}
