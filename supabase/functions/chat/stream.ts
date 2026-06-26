/**
 * chat/stream.ts — LLM streaming response handling, card rendering, citation management.
 */

import type { ChatTurn } from '../_shared/gemini.ts';
import { streamChat } from '../_shared/gemini.ts';
import {
  buildTournamentCards,
  type TournamentCardRow,
} from '../_shared/chat_cards.ts';
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
  const ruleCitations: DbCitation[] = rules.slice(0, 3).map((r) => ({
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

/** Build tournament card UI blocks from SemanticTournament[]. */
export function buildTournamentCardBlocks(tournaments: SemanticTournament[]): unknown {
  if (tournaments.length === 0) return null;
  const cardRows: TournamentCardRow[] = tournaments.slice(0, 10).map((t) => ({
    id: t.id,
    sport: t.sport as 'tennis' | 'futsal',
    title: t.title,
    start_date: t.start_date,
    end_date: null,
    application_deadline: null,
    region: t.region ?? null,
    location: null,
    eligible_grades: t.eligible_grades ?? [],
    entry_fee: null,
    format: null,
    regulation_fields: t.regulation_fields,
  }));
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

  for await (
    const evt of streamChat(history, {
      systemInstruction: systemPrompt,
    })
  ) {
    if (evt.type === 'text' && evt.text) {
      assistantText += evt.text;
      send('delta', { text: evt.text });
    } else if (evt.type === 'error') {
      llmErrored = true;
      send('error', { message: evt.error });
    }
  }

  return { assistantText, errored: llmErrored };
}
