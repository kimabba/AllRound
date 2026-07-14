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
  division: string | null;
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
  source: 'tournaments' | 'rules' | 'venues' | 'clubs';
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

// Intent classifier settings.
// 임베딩 KNN 관측용 하한 — intent_classify RPC 가 이 값 이상 유사한 예시만 다수결에 포함.
export const INTENT_KNN_THRESHOLD = 0.75;

// 라우팅(검색 실제 실행) 게이트. 룰 분류(confidence=1.0)만 이 문턱을 넘는다.
// 임베딩 분류는 confidence=cosine similarity 이고 실측상 상한이 ~0.86 (JY-107) 이라
// 이 게이트를 구조적으로 넘지 못한다 → 의도된 shadow-only 동작이다. 버그 아님.
// 근거: 시드(intent 당 7개) leave-one-out 정확도 67%, 오분류의 similarity 가 정확분류보다
// 높아 similarity 임계값으로 correct/wrong 을 분리할 수 없다. 문턱을 낮추면 ~33% 오라우팅.
// 시드 대폭 보강 + 정확도 재평가 전까지 임베딩 라우팅을 켜지 않는다.
export const ROUTING_CONFIDENCE_THRESHOLD = 0.95;

// Regulation RAG context token management (migration 077)
export const REGULATION_BODY_TOP_N = 2;
export const REGULATION_BODY_CONTEXT_CAP = 1200;
