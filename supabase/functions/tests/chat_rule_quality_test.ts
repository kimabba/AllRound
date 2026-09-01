import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';

import { buildContextPrompt, buildSystemPrompt, selectGroundedRules } from '../chat/context.ts';
import type { SemanticRule } from '../chat/types.ts';
import { RULE_GROUNDING_MIN_SIMILARITY } from '../chat/types.ts';

function rule(title: string, similarity: number): SemanticRule {
  return {
    id: `id-${title}`,
    sport: 'tennis',
    category: '경기운영',
    title,
    body: '타이브레이크 운영 규정 본문',
    similarity,
  };
}

Deno.test('룰북 답변은 제공된 문서 제목을 근거로 명시한다', () => {
  const prompt = buildSystemPrompt();
  assertStringIncludes(prompt, '근거 문서: <제공된 룰북 제목>');
  assertStringIncludes(prompt, '제목을 바꾸거나 내부 id로 대신하지 마세요');
});

Deno.test('관련 룰북이 없으면 일반 상식을 DB 근거처럼 말하지 않는다', () => {
  const prompt = buildSystemPrompt();
  assertStringIncludes(prompt, '현재 올라운드 DB에서 관련 룰북 문서를 찾지 못했습니다');
  assertStringIncludes(prompt, '"일반적인 규칙 안내"로 분리');
  assertStringIncludes(prompt, 'DB나 특정 문서에서 확인한 내용처럼 말하지 마세요');
});

Deno.test('이미 출시된 동호인 랭킹을 준비 중 기능으로 안내하지 않는다', () => {
  const prompt = buildSystemPrompt();
  assertEquals(prompt.includes('동호인 랭킹·레벨 시스템'), false);
});

Deno.test('유사도 하한 미만 룰북은 컨텍스트 근거에서 제외한다', () => {
  const low = rule('무관한 문서', RULE_GROUNDING_MIN_SIMILARITY - 0.001);
  assertEquals(selectGroundedRules([low]), []);
  assertEquals(buildContextPrompt([], [low]), '');
});

Deno.test('유사도 하한을 통과한 룰북은 제목과 함께 컨텍스트에 제공한다', () => {
  const grounded = rule('KTA 타이브레이크 규정', RULE_GROUNDING_MIN_SIMILARITY);
  assertEquals(selectGroundedRules([grounded]), [grounded]);
  assertStringIncludes(buildContextPrompt([], [grounded]), 'KTA 타이브레이크 규정');
});
