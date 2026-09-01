import { assertEquals } from 'std/assert/mod.ts';
import {
  CHAT_SAFETY_SETTINGS,
  parseGeminiStreamChunk,
  parseStructuredResponse,
} from '../_shared/gemini.ts';

Deno.test('parseStructuredResponse: candidates parts.text JSON 파싱', () => {
  const raw = { candidates: [{ content: { parts: [{ text: '{"a":1,"b":"x"}' }] } }] };
  const out = parseStructuredResponse<{ a: number; b: string }>(raw);
  assertEquals(out.a, 1);
  assertEquals(out.b, 'x');
});

Deno.test('채팅 Gemini 요청은 네 가지 안전 범주를 명시적으로 켠다', () => {
  assertEquals(CHAT_SAFETY_SETTINGS, [
    {
      category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
      threshold: 'BLOCK_LOW_AND_ABOVE',
    },
    {
      category: 'HARM_CATEGORY_HARASSMENT',
      threshold: 'BLOCK_MEDIUM_AND_ABOVE',
    },
    {
      category: 'HARM_CATEGORY_HATE_SPEECH',
      threshold: 'BLOCK_MEDIUM_AND_ABOVE',
    },
    {
      category: 'HARM_CATEGORY_DANGEROUS_CONTENT',
      threshold: 'BLOCK_MEDIUM_AND_ABOVE',
    },
  ]);
});

Deno.test('Gemini promptFeedback 차단을 텍스트 없는 blocked 청크로 좁힌다', () => {
  assertEquals(
    parseGeminiStreamChunk({
      promptFeedback: { blockReason: 'SAFETY' },
      usageMetadata: { promptTokenCount: 5, totalTokenCount: 5 },
    }),
    {
      text: '',
      usage: { promptTokenCount: 5, totalTokenCount: 5 },
      blockReason: 'SAFETY',
    },
  );
});

Deno.test('Gemini candidate SAFETY 종료는 응답 본문을 노출하지 않는다', () => {
  assertEquals(
    parseGeminiStreamChunk({
      candidates: [{
        finishReason: 'SAFETY',
        content: { parts: [{ text: '노출되면 안 되는 내용' }] },
      }],
    }),
    { text: '', blockReason: 'SAFETY' },
  );
});

Deno.test('정상 Gemini 청크는 thought를 빼고 텍스트만 합친다', () => {
  assertEquals(
    parseGeminiStreamChunk({
      candidates: [{
        finishReason: 'STOP',
        content: {
          parts: [
            { text: '안녕' },
            { thought: true, text: '숨은 생각' },
            { text: '하세요' },
          ],
        },
      }],
    }),
    { text: '안녕하세요' },
  );
});
