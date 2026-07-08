/**
 * Gemini API 사용량 기록 (gemini_usage 테이블, migration 082).
 *
 * 절대 throw 하지 않는다 — 기록 실패가 채팅 흐름을 깨면 안 됨.
 */

import type { SupabaseClient } from '@supabase/supabase-js';

export interface GeminiUsageRecord {
  kind: 'llm' | 'embedding';
  model: string;
  inputTokens?: number | null;
  outputTokens?: number | null;
  totalTokens?: number | null;
  userId?: string | null;
  context?: string | null;
}

/** service_role 클라이언트로 gemini_usage insert. 실패는 warn 로그만. */
export async function recordGeminiUsage(
  client: SupabaseClient,
  usage: GeminiUsageRecord,
): Promise<void> {
  try {
    const { error } = await client.from('gemini_usage').insert({
      kind: usage.kind,
      model: usage.model,
      input_tokens: usage.inputTokens ?? null,
      output_tokens: usage.outputTokens ?? null,
      total_tokens: usage.totalTokens ?? null,
      user_id: usage.userId ?? null,
      context: usage.context ?? null,
    });
    if (error) console.warn('recordGeminiUsage failed:', error.message);
  } catch (e) {
    console.warn('recordGeminiUsage failed:', (e as Error).message);
  }
}
