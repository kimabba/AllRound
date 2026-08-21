/**
 * chat/types.ts — All type definitions and constants for the chat function.
 */

import type { RegulationField } from '../_shared/regulation.ts';

export interface ChatBody {
  message: string;
  conversation_id?: string;
  active_sport?: string;
  selected_entity?: unknown;
  // 대회검색 정제 칩 재요청(JY-101). 있으면 intent 분류를 건너뛰고 이 슬롯으로 바로 검색한다.
  // 페이로드 파싱/타입은 _shared/chat_cards.ts 의 parseTournamentRefine/TournamentRefine.
  tournament_refine?: unknown;
}

export interface UserSport {
  sport: string;
  grade: string;
  is_primary: boolean;
  /**
   * user_sports 조회 시 `grades(label_ko)` 로 임베드한 등급 라벨(#319 — 라벨 정본은 DB).
   * user_sports.grade 는 grades 로 복합 FK 가 걸려 있어 항상 한 행이 대응하지만,
   * PostgREST 가 to-one 으로 못 좁히면 배열로 올 수 있어 두 형태를 모두 받는다(gradeLabelOf).
   */
  grades?: { label_ko: string } | { label_ko: string }[] | null;
}

export interface UserTennisOrgRow {
  org: string;
  division: string | null;
  division_codes: string[];
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
  source: 'tournaments' | 'rules' | 'venues' | 'clubs' | 'rankings';
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

/**
 * 프롬프트·컨텍스트 조립이 바뀌면 이 값을 올린다.
 *
 * 의미 캐시 키(`computeUserContextHash`)에 들어가므로, 올리는 순간 기존 캐시가
 * 전부 미스가 되고 새 프롬프트로 답이 다시 만들어진다. 안 올리면 배포해도 TTL
 * (24시간) 동안 옛 프롬프트로 만든 답이 계속 나간다 — 내부 UUID 노출을 고치고도
 * 하루 동안 그대로 보였을 상황이 실제로 있었다(#363, codex 리뷰가 잡음).
 *
 * v3: 컨텍스트 행에서 내부 id 제거 + "출처는 제목으로" 지시로 교체.
 * v4: 스포츠·앱 답변 범위, 근거 없는 사실 생성 금지, 유해 요청 거절을 명시.
 * v5: 룰북 제목 인용 계약 + 관련 문서가 없을 때 DB 근거를 가장하지 않도록 강화.
 */
export const CHAT_PROMPT_VERSION = 5;

// rules_semantic_search 는 유사도 하한 없이 상위 N개를 항상 반환한다. 운영 점검에서
// 테니스 타이브레이크 질문에 무관한 문서가 0.66~0.69로 잡혔고, 관련 풋살 문서는
// 0.82 이상이었다. 관측된 오답 구간을 제외하기 위해 0.72 미만은 DB 근거로 쓰지 않는다.
export const RULE_GROUNDING_MIN_SIMILARITY = 0.72;

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
