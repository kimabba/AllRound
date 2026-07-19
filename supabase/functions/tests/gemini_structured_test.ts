import { assertEquals } from 'std/assert/mod.ts';
import { parseStructuredResponse } from '../_shared/gemini.ts';

Deno.test('parseStructuredResponse: candidates parts.text JSON 파싱', () => {
  const raw = { candidates: [{ content: { parts: [{ text: '{"a":1,"b":"x"}' }] } }] };
  const out = parseStructuredResponse<{ a: number; b: string }>(raw);
  assertEquals(out.a, 1);
  assertEquals(out.b, 'x');
});
