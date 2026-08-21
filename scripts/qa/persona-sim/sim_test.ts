import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseChatSse } from './sim.ts';

const sse = (blocks: Array<[string, unknown]>) =>
  blocks.map(([ev, data]) => `event: ${ev}\ndata: ${JSON.stringify(data)}`).join('\n\n') + '\n\n';

Deno.test('parseChatSse: intent + delta 정상 스트림', () => {
  const text = sse([
    ['intent', { intent: 'tournament_search' }],
    ['delta', { text: '안녕' }],
    ['delta', { text: '하세요' }],
    ['done', {}],
  ]);
  assertEquals(parseChatSse(text), { intent: 'tournament_search', answer: '안녕하세요', error: false });
});

Deno.test('parseChatSse: 서버 예외는 done 없이 error 이벤트만 오고, 놓치면 안 된다', () => {
  const text = sse([
    ['meta', { conversation_id: 'c1' }],
    ['error', { message: 'db down' }],
  ]);
  const result = parseChatSse(text);
  assertEquals(result.error, true);
  assertEquals(result.intent, '');
});

Deno.test('parseChatSse: 핸들링된 오류 문구(delta 안)도 여전히 에러로 잡힌다', () => {
  const text = sse([
    ['delta', { text: '일시적인 시스템 오류로 일정을 확인하지 못했습니다.' }],
    ['done', {}],
  ]);
  assertEquals(parseChatSse(text).error, true);
});
