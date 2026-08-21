/**
 * chat/stream.ts — LLM streaming response handling, card rendering, citation management.
 */

import type { ChatTurn, GeminiUsage } from '../_shared/gemini.ts';
import { streamChat } from '../_shared/gemini.ts';
import { buildTournamentCards, type TournamentCardRow } from '../_shared/chat_cards.ts';
import type { Sport } from '../_shared/enums.ts';
import { normalizeRegulationFields } from '../_shared/regulation.ts';
import { selectGroundedRules } from './context.ts';
import { GEMINI_SAFETY_REFUSAL } from './safety.ts';
import type { DbCitation, SemanticRule, SemanticTournament, VenueRow } from './types.ts';

/** Build DB citations from RAG results. */
export function buildDbCitations(
  tournaments: SemanticTournament[],
  rules: SemanticRule[],
  venues: VenueRow[],
): DbCitation[] {
  const dbCitations: DbCitation[] = tournaments.slice(0, 5).map((t) => ({
    type: 'db' as const,
    source: 'tournaments',
    id: t.id,
    title: t.title,
  }));
  const ruleCitations: DbCitation[] = selectGroundedRules(rules).map((r) => ({
    type: 'db' as const,
    source: 'rules',
    id: r.id,
    title: r.title,
  }));
  const venueCitations: DbCitation[] = venues.slice(0, 15).map((v) => ({
    type: 'db' as const,
    source: 'venues' as const,
    id: v.id,
    title: v.name,
  }));
  return [...dbCitations, ...ruleCitations, ...venueCitations];
}

/**
 * 응답 의도에 맞는 DB 인용을 고른다.
 *
 * rule_lookup 은 검색 결과 중 관련성이 확인된 룰북만 내려 무관한 대회·구장 출처가
 * 섞이지 않게 한다. index.ts 는 이 순수 헬퍼를 호출해 citation SSE와 저장값에 같은
 * 배열을 사용하면 된다.
 */
export function buildResponseDbCitations(
  intent: string,
  tournaments: SemanticTournament[],
  rules: SemanticRule[],
  venues: VenueRow[],
): DbCitation[] {
  if (intent === 'rule_lookup') {
    return buildDbCitations([], rules, []);
  }
  return buildDbCitations(tournaments, rules, venues);
}

/** Build tournament card UI blocks from SemanticTournament[]. */
export function buildTournamentCardBlocks(tournaments: SemanticTournament[]): unknown {
  if (tournaments.length === 0) return null;
  const cardRows: TournamentCardRow[] = tournaments.slice(0, 10).map((t) => {
    // SemanticTournament(RAG)엔 location 필드가 없어 요강에서 장소를 끌어올린다.
    // 카드 간소화로 요강 칩을 없앤 뒤에도 장소가 상단 InfoRow 에 남도록.
    // 마감은 semantic_search 가 application_deadline 컬럼을 반환하지 않고 요강에도
    // 마감 라벨이 없어 RAG 카드엔 표시 불가(상세 화면에서 확인).
    const reg = normalizeRegulationFields(t.regulation_fields);
    const location = reg.find((f) => ['장소', '경기장', '대회장'].includes(f.label))?.value ??
      null;
    return {
      id: t.id,
      sport: t.sport as Sport,
      title: t.title,
      start_date: t.start_date,
      end_date: null,
      application_deadline: null,
      region: t.region ?? null,
      location,
      eligible_grades: t.eligible_grades ?? [],
      entry_fee: null,
      format: null,
      regulation_fields: t.regulation_fields,
    };
  });
  return {
    blocks: [
      {
        type: 'cards',
        entity: 'tournament',
        items: buildTournamentCards(cardRows),
      },
    ],
  };
}

export interface StreamLlmResult {
  assistantText: string;
  errored: boolean;
  blocked: boolean;
  blockReason?: string;
  usage?: GeminiUsage;
}

/**
 * Stream LLM response and send delta events.
 * Returns the accumulated assistant text and whether an error occurred.
 */
export async function streamLlmResponse(
  history: ChatTurn[],
  systemPrompt: string,
  send: (event: string, data: unknown) => void,
): Promise<StreamLlmResult> {
  let assistantText = '';
  let llmErrored = false;
  let blocked = false;
  let blockReason: string | undefined;
  let usage: GeminiUsage | undefined;

  for await (
    const evt of streamChat(history, {
      systemInstruction: systemPrompt,
    })
  ) {
    if (evt.type === 'text' && evt.text && !blocked) {
      assistantText += evt.text;
      send('delta', { text: evt.text });
    } else if (evt.type === 'error') {
      llmErrored = true;
      send('error', { message: evt.error });
    } else if (evt.type === 'blocked') {
      blocked = true;
      blockReason = evt.blockReason;
      assistantText = GEMINI_SAFETY_REFUSAL;
      send('delta', { text: GEMINI_SAFETY_REFUSAL });
    } else if (evt.type === 'done' && evt.usage) {
      usage = evt.usage;
    }
  }

  return { assistantText, errored: llmErrored, blocked, blockReason, usage };
}
