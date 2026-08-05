import { assert, assertEquals, assertStringIncludes } from 'std/assert/mod.ts';

import { buildContextPrompt, buildSystemPrompt } from '../chat/context.ts';
import type { SemanticRule, SemanticTournament, VenueRow } from '../chat/types.ts';

// 모델 컨텍스트에 내부 UUID 를 넣으면 답변 본문에 그대로 새어나온다.
// 2026-07-21 웹 E2E 에서 "동률 처리 (참고: id: f2d50bc7-8d2f-4045-b067-bc81b6fa8695)"
// 같은 문자열이 실제로 사용자에게 보였다 — 시스템 프롬프트가 "출처는 DB id로만
// 명시" 라고 지시했고 모델은 그대로 따랐다.
//
// 인용 카드는 buildDbCitations() 가 원본 배열에서 따로 만들고(chat/stream.ts),
// 모델 응답에서 id 를 파싱하는 경로는 없다. 그래서 컨텍스트에서는 빼는 게 맞다.

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

const TOURNAMENT_ID = 'f2d50bc7-8d2f-4045-b067-bc81b6fa8695';
const RULE_ID = 'c1c8aa11-441b-8e51-a7a4-40a9ede1b0c2';
const VENUE_ID = 'aa11bb22-cc33-dd44-ee55-ff6677889900';

function tourn(over: Partial<SemanticTournament> = {}): SemanticTournament {
  return {
    id: TOURNAMENT_ID,
    sport: 'tennis',
    title: '제30회 토요피닉스배',
    start_date: '2026-09-27',
    region: '광주',
    eligible_grades: ['개나리부'],
    regulation_fields: [],
    regulation_body: null,
    similarity: 0.9,
    ...over,
  };
}

function rule(over: Partial<SemanticRule> = {}): SemanticRule {
  return {
    id: RULE_ID,
    sport: 'tennis',
    category: '경기운영',
    title: '동률 처리',
    body: '세트 스코어가 같으면 게임 득실차로 순위를 가른다.',
    similarity: 0.8,
    ...over,
  };
}

function venue(over: Partial<VenueRow> = {}): VenueRow {
  return {
    id: VENUE_ID,
    sport: 'tennis',
    name: '염주종합체육관',
    region: '광주',
    address: '서구 화정동',
    venue_type: 'outdoor',
    court_count: 8,
    phone: null,
    ...over,
  } as VenueRow;
}

Deno.test('컨텍스트 블록에 내부 UUID 가 들어가지 않는다', () => {
  const prompt = buildContextPrompt([tourn()], [rule()], [venue()]);

  assert(
    !UUID_RE.test(prompt),
    `컨텍스트에 UUID 가 남아 있다 — 모델이 답변 본문에 그대로 쓴다:\n${prompt}`,
  );
  // id 만 빠지고 내용은 그대로여야 한다.
  assertStringIncludes(prompt, '제30회 토요피닉스배');
  assertStringIncludes(prompt, '동률 처리');
  assertStringIncludes(prompt, '염주종합체육관');
});

Deno.test('세 종류 id 가 각각 빠졌는지 개별 확인', () => {
  const prompt = buildContextPrompt([tourn()], [rule()], [venue()]);

  for (
    const [label, id] of Object.entries({
      대회: TOURNAMENT_ID,
      규칙: RULE_ID,
      구장: VENUE_ID,
    })
  ) {
    assertEquals(
      prompt.includes(id),
      false,
      `${label} id 가 컨텍스트에 남아 있다`,
    );
  }
});

// 프롬프트만 고치고 캐시 키를 그대로 두면, 배포해도 TTL(24시간) 동안 옛 프롬프트로
// 만든 답이 계속 나간다 — UUID 를 지우고도 하루는 그대로 보인다(codex 리뷰가 잡음).
// 캐시 키는 임베딩·사용자·프로필 해시뿐이라 프롬프트 변경을 모른다.
Deno.test('캐시 키에 프롬프트 버전이 들어간다', async () => {
  const src = await Deno.readTextFile(
    new URL('../chat/context.ts', import.meta.url),
  );
  assertStringIncludes(
    src,
    'v: CHAT_PROMPT_VERSION',
    'computeUserContextHash 의 payload 에 프롬프트 버전이 있어야 한다 —' +
      ' 없으면 프롬프트를 바꿔도 옛 답이 캐시에서 그대로 재사용된다',
  );
});

Deno.test('시스템 프롬프트가 id 를 출처로 쓰라고 시키지 않는다', () => {
  const prompt = buildSystemPrompt();

  assertEquals(
    prompt.includes('출처는 DB id로만 명시'),
    false,
    '이 지시가 UUID 노출의 직접 원인이었다 — 모델은 지시를 따랐을 뿐이다',
  );
  assertStringIncludes(prompt, '내부 id는 답변에 쓰지 않습니다');
});
