/**
 * chat/types.ts — All type definitions and constants for the chat function.
 */

import type { RegulationField } from '../_shared/regulation.ts';

export interface ChatBody {
  message: string;
  conversation_id?: string;
  active_sport?: string;
  selected_entity?: unknown;
}

export interface UserSport {
  sport: string;
  grade: string;
  is_primary: boolean;
}

export interface UserTennisOrgRow {
  org: string;
  division_local: string | null;
  score: number | null;
  is_primary: boolean;
  region_code: string | null;
}

export interface SemanticTournament {
  id: string;
  sport: string;
  title: string;
  start_date: string;
  region: string | null;
  eligible_grades: string[];
  regulation_fields: RegulationField[];
  regulation_body: string | null;
  similarity: number;
}

export interface RawSemanticTournament {
  id: string;
  sport: string;
  title: string;
  start_date: string;
  region: string | null;
  eligible_grades: string[] | null;
  regulation_fields: unknown;
  regulation_body: string | null;
  similarity: number;
}

export interface SemanticRule {
  id: string;
  sport: string;
  category: string;
  title: string;
  body: string;
  similarity: number;
}

export interface VenueRow {
  id: string;
  sport: string;
  name: string;
  region: string;
  address: string | null;
  venue_type: string;
  court_count: number | null;
  phone: string | null;
  website: string | null;
}

export interface DbCitation {
  type: 'db';
  source: 'tournaments' | 'rules' | 'venues';
  id: string;
  title: string;
}

export interface QaCacheHit {
  id: string;
  answer_text: string;
  citations: DbCitation[];
  similarity: number;
}

export interface IntentClassifyRow {
  intent: string;
  similarity: number;
}

// Semantic cache settings
export const QA_CACHE_THRESHOLD = 0.92;
export const QA_CACHE_TTL_HOURS = 24;

// Intent classifier settings
export const INTENT_KNN_THRESHOLD = 0.75;

// Day 5-6 routing settings
export const ROUTING_CONFIDENCE_THRESHOLD = 0.95;

// Regulation RAG context token management (migration 077)
export const REGULATION_BODY_TOP_N = 2;
export const REGULATION_BODY_CONTEXT_CAP = 1200;
