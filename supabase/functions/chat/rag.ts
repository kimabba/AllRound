/**
 * chat/rag.ts — RAG search (tournament + rule semantic search), venue search, context assembly.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { REGION_LABELS, type RegionCode } from '../_shared/enums.ts';
import { normalizeRegulationFields } from '../_shared/regulation.ts';
import type {
  RawSemanticTournament,
  SemanticRule,
  SemanticTournament,
  VenueRow,
} from './types.ts';

/** RPC raw result (unknown jsonb) -> SemanticTournament[] safely narrowed. */
export function normalizeSemanticTournaments(rows: unknown): SemanticTournament[] {
  if (!Array.isArray(rows)) return [];
  return (rows as RawSemanticTournament[]).map((r) => ({
    id: r.id,
    sport: r.sport,
    title: r.title,
    start_date: r.start_date,
    region: r.region ?? null,
    eligible_grades: Array.isArray(r.eligible_grades) ? r.eligible_grades : [],
    regulation_fields: normalizeRegulationFields(r.regulation_fields),
    regulation_body: r.regulation_body ?? null,
    similarity: r.similarity,
  }));
}

export interface RagResult {
  tournaments: SemanticTournament[];
  rules: SemanticRule[];
  venues: VenueRow[];
  errored: boolean;
}

/**
 * Perform semantic RAG search for tournaments and rules.
 * Returns empty results if vectorLiteral is missing.
 */
export async function performRagSearch(
  supabase: SupabaseClient,
  vectorLiteral: string,
  explicitSport: string | null,
  userId: string,
): Promise<RagResult> {
  const result: RagResult = { tournaments: [], rules: [], venues: [], errored: false };

  try {
    const [tRes, rRes] = await Promise.all([
      supabase.rpc('tournaments_semantic_search', {
        p_user_id: userId,
        p_query_embedding: vectorLiteral,
        p_only_my_grade: false,
        p_match_count: 5,
        p_sport: explicitSport ?? null,
      }),
      supabase.rpc('rules_semantic_search', {
        p_query_embedding: vectorLiteral,
        p_sport: explicitSport ?? null,
        p_match_count: 3,
      }),
    ]);

    if (tRes.error || rRes.error) {
      result.errored = true;
      console.error('RAG RPC error:', tRes.error?.message, rRes.error?.message);
    }
    result.tournaments = normalizeSemanticTournaments(tRes.data);
    result.rules = (rRes.data as SemanticRule[]) ?? [];
  } catch (e) {
    result.errored = true;
    console.error('RAG failed:', (e as Error).message);
  }

  return result;
}

/**
 * Perform venue search via RPC.
 */
export async function performVenueSearch(
  supabase: SupabaseClient,
  requestedSport: string | null,
  regionSlot: string | undefined,
): Promise<{ venues: VenueRow[]; errored: boolean }> {
  try {
    const regionDisplay = regionSlot
      ? (REGION_LABELS[regionSlot as RegionCode]
        ? REGION_LABELS[regionSlot as RegionCode] + '시'
        : null)
      : null;
    const { data: vData, error: vErr } = await supabase.rpc('venues_search', {
      p_sport: requestedSport ?? null,
      p_region: regionDisplay ?? regionSlot ?? null,
      p_limit: 15,
    });
    if (vErr) {
      console.error('venues_search error:', vErr.message);
      return { venues: [], errored: true };
    }
    return { venues: (vData as VenueRow[]) ?? [], errored: false };
  } catch (e) {
    console.error('venues_search failed:', (e as Error).message);
    return { venues: [], errored: true };
  }
}
