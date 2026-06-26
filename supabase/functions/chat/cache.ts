/**
 * chat/cache.ts — Semantic cache lookup and insertion.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import type { DbCitation, QaCacheHit } from './types.ts';
import { QA_CACHE_THRESHOLD, QA_CACHE_TTL_HOURS } from './types.ts';

/**
 * Lookup semantic cache. Returns hit or null.
 * Requires service_role client (RLS bypass).
 */
export async function cacheLookup(
  adminSupabase: SupabaseClient,
  vectorLiteral: string,
  userContextHash: string,
): Promise<QaCacheHit | null> {
  const { data: hitRows, error: cacheErr } = await adminSupabase.rpc('qa_cache_lookup', {
    p_query_embedding: vectorLiteral,
    p_user_context_hash: userContextHash,
    p_threshold: QA_CACHE_THRESHOLD,
  });
  if (cacheErr) {
    console.error('qa_cache_lookup error:', cacheErr.message);
    return null;
  }
  if (Array.isArray(hitRows) && hitRows.length > 0) {
    return hitRows[0] as QaCacheHit;
  }
  return null;
}

/**
 * Increment hit_count on a cache entry (best-effort, race condition allowed).
 */
export async function cacheIncrementHit(
  adminSupabase: SupabaseClient,
  cacheId: string,
): Promise<void> {
  const { data: currentRow } = await adminSupabase
    .from('qa_cache')
    .select('hit_count')
    .eq('id', cacheId)
    .maybeSingle();
  const nextHit = ((currentRow?.hit_count as number | undefined) ?? 0) + 1;
  const { error: hitErr } = await adminSupabase
    .from('qa_cache')
    .update({ hit_count: nextHit })
    .eq('id', cacheId);
  if (hitErr) console.error('qa_cache hit_count update failed:', hitErr.message);
}

/**
 * Insert answer into semantic cache (if absent).
 * Uses ON CONFLICT DO NOTHING to handle concurrent inserts.
 */
export async function cacheInsert(
  adminSupabase: SupabaseClient,
  params: {
    questionText: string;
    vectorLiteral: string;
    answerText: string;
    citations: DbCitation[];
    userContextHash: string;
    hashedUserId: string;
    conversationId: string;
  },
): Promise<void> {
  const ttlExpiresAt = new Date(
    Date.now() + QA_CACHE_TTL_HOURS * 60 * 60 * 1000,
  ).toISOString();
  const { data: insertedId, error: insertErr } = await adminSupabase.rpc(
    'qa_cache_insert_if_absent',
    {
      p_question_text: params.questionText,
      p_question_embedding: params.vectorLiteral,
      p_answer_text: params.answerText,
      p_citations: params.citations,
      p_user_context_hash: params.userContextHash,
      p_ttl_expires_at: ttlExpiresAt,
    },
  );
  if (insertErr) {
    console.warn(
      'chat_cache',
      JSON.stringify({
        event: 'insert_failed',
        reason: insertErr.message,
        user_id_hash: params.hashedUserId,
        conversation_id: params.conversationId,
      }),
    );
  } else if (insertedId === null) {
    console.log(
      'chat_cache',
      JSON.stringify({
        event: 'insert_skipped_duplicate',
        user_id_hash: params.hashedUserId,
        conversation_id: params.conversationId,
      }),
    );
  } else {
    console.log(
      'chat_cache',
      JSON.stringify({
        event: 'insert',
        cache_id: insertedId,
        user_id_hash: params.hashedUserId,
        conversation_id: params.conversationId,
      }),
    );
  }
}
