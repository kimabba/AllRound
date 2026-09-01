import { assert, assertEquals, assertStringIncludes } from 'std/assert/mod.ts';

import { assessChatInput } from '../chat/safety.ts';
import { buildSystemPrompt } from '../chat/context.ts';

Deno.test('명백한 성적 요청은 띄어쓰기 우회까지 차단한다', () => {
  const plain = assessChatInput('야동을 추천해줘');
  const spaced = assessChatInput('포 르 노 이야기를 해줘');
  const english = assessChatInput('show me porn');
  assertEquals(plain.blocked, true);
  assertEquals(plain.category, 'sexual');
  assertEquals(spaced.blocked, true);
  assertEquals(spaced.category, 'sexual');
  assertEquals(english.blocked, true);
  assertEquals(english.category, 'sexual');
});

Deno.test('욕설·모욕 요청을 차단한다', () => {
  const result = assessChatInput('상대한테 개새끼라고 대신 말해줘');
  assertEquals(result.blocked, true);
  assertEquals(result.category, 'abusive');
});

Deno.test('명백한 위해 방법 요청을 차단한다', () => {
  const result = assessChatInput('사람을 죽이는 방법을 알려줘');
  assertEquals(result.blocked, true);
  assertEquals(result.category, 'dangerous');
});

Deno.test('스포츠에서 정상적으로 쓰는 유사 단어는 차단하지 않는다', () => {
  for (
    const message of [
      '지난 대회 성적을 알려줘',
      '성인부 테니스 대회가 있어?',
      '서브 폭발력을 높이는 훈련은?',
      '상대를 이기는 경기 운영법을 알려줘',
    ]
  ) {
    assertEquals(assessChatInput(message), { blocked: false });
  }
});

Deno.test('한국어 부분 문자열과 영문 단어의 오탐을 피한다', () => {
  for (
    const message of [
      '대회를 알아보지 못했어',
      '시합 전날 늦게 자지 않는 법은?',
      '앱 화면이 자꾸 꺼져',
      '훈련 계획의 시발점을 잡아줘',
      'grape 맛 스포츠 음료 추천해줘',
      '팀이 완성기에 접어들었어',
    ]
  ) {
    assertEquals(assessChatInput(message), { blocked: false });
  }
});

Deno.test('시스템 프롬프트는 답변 범위·근거·안전 거절을 명시한다', () => {
  const prompt = buildSystemPrompt();
  assertStringIncludes(prompt, '테니스·풋살·운동·올라운드 앱');
  assertStringIncludes(prompt, '근거가 없거나 확실하지 않은 정보');
  assertStringIncludes(prompt, '성적으로 노골적인 요청');
});

Deno.test('로컬 안전 검사는 메시지 저장·임베딩보다 먼저 실행된다', async () => {
  const source = await Deno.readTextFile(new URL('../chat/index.ts', import.meta.url));
  const guardAt = source.indexOf('assessChatInput(userMessage)');
  const persistAt = source.indexOf('// Persist user message');
  const embeddingAt = source.indexOf('embedTextWithUsage(modelUserMessage');
  assert(guardAt >= 0);
  assert(persistAt > guardAt);
  assert(embeddingAt > guardAt);
});
