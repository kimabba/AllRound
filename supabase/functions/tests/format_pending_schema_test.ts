import { assert } from 'std/assert/mod.ts';
import { buildRegulationPrompt, RESPONSE_SCHEMA } from '../format-pending/logic.ts';

/**
 * Gemini 는 response_schema 의 enum 값을 문자열로만 받는다. 숫자가 하나라도 있으면
 * 요청 전체가 400 INVALID_ARGUMENT 로 거부되고, 정형화 파이프라인이 통째로 멈춘다.
 * 실제로 그렇게 3주간(2026-07-29 ~ 08-19) 단 한 건도 정형화되지 않았고, cron 은
 * 200 만 반환해 아무도 몰랐다. 스키마에 enum 을 추가할 때 이 테스트가 방어한다.
 */
function collectEnums(node: unknown, path: string, out: Array<[string, unknown[]]>): void {
  if (Array.isArray(node)) {
    node.forEach((item, i) => collectEnums(item, `${path}[${i}]`, out));
    return;
  }
  if (typeof node !== 'object' || node === null) return;
  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (key === 'enum' && Array.isArray(value)) out.push([`${path}.enum`, value]);
    else collectEnums(value, `${path}.${key}`, out);
  }
}

Deno.test('format-pending 응답 스키마의 enum 값은 전부 문자열이다', () => {
  const found: Array<[string, unknown[]]> = [];
  collectEnums(RESPONSE_SCHEMA, 'RESPONSE_SCHEMA', found);
  assert(found.length > 0, 'enum 을 하나도 못 찾았다 — 탐색이 깨진 것');
  for (const [path, values] of found) {
    for (const value of values) {
      assert(
        typeof value === 'string',
        `${path} 에 문자열이 아닌 값(${JSON.stringify(value)})이 있다 — Gemini 가 400 을 낸다`,
      );
    }
  }
});

Deno.test('등급·부서별 참가 자격은 비교 표로 정리하도록 지시한다', () => {
  const prompt = buildRegulationPrompt('테스트 대회', '원본 요강');
  assert(prompt.includes('등급·부서별 참가 자격'));
  assert(prompt.includes('paragraph로 합치지 말고 table'));
  assert(prompt.includes('출전 기준'));
});
