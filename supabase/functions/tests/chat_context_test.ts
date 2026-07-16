import { assert, assertEquals } from 'std/assert/mod.ts';
import { buildContextPrompt, buildSystemPrompt } from '../chat/context.ts';
import type { SemanticTournament } from '../chat/types.ts';

const TOURNAMENT_ID = '11111111-1111-1111-1111-111111111111';

const TOURNAMENT: SemanticTournament = {
  id: TOURNAMENT_ID,
  sport: 'tennis',
  title: '광주 테니스 오픈',
  start_date: '2026-08-01',
  region: '광주',
  eligible_grades: ['gj_m_gold'],
  regulation_fields: [],
  regulation_body: null,
  similarity: 0.9,
};

Deno.test('system prompt forbids exposing internal database ids', () => {
  const prompt = buildSystemPrompt([], []);

  assert(prompt.includes('내부 DB id·UUID는 답변 본문에 절대 표시하지 않습니다'));
  assert(!prompt.includes('출처는 DB id로만 명시합니다'));
});

Deno.test('RAG context keeps titles but omits internal tournament ids', () => {
  const prompt = buildContextPrompt([TOURNAMENT], []);

  assert(prompt.includes(TOURNAMENT.title));
  assertEquals(prompt.includes(TOURNAMENT_ID), false);
  assertEquals(prompt.includes('(id:'), false);
});
