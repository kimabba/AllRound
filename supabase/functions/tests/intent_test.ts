import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildRuleResult,
  classifyByRule,
  extractDateRange,
  extractSlots,
  type Intent,
  type IntentResult,
  resolveRequestedSport,
  type Slots,
} from '../_shared/intent.ts';

/**
 * Intent 분류기 회귀 테스트 (JY-10, 비용절감 계획 Day 7 — 품질 샘플 검증).
 *
 * 목적:
 *   1. 정형 질문 커버리지 — 어떤 한국어 질문이 룰로 분류되어 LLM 없이 처리 가능한지 고정.
 *   2. 슬롯 추출 정확도 — region/sport/date_range 가 의도와 독립적으로 뽑히는지 검증.
 *   3. 우선순위 룰 회귀 — tournament > detail/my_profile, match 는 schedule 동반 필요 등.
 *
 * 날짜 의존 케이스를 결정적으로 만들기 위해 고정 시각을 사용한다.
 *   FIXED_NOW = 2026-06-07T03:00:00Z = KST 2026-06-07(일) 12:00.
 *   → "오늘" = 2026-06-07, "이번 주"(월~일) = 2026-06-01 ~ 2026-06-07.
 */
const FIXED_NOW = new Date('2026-06-07T03:00:00.000Z');

interface RuleCase {
  msg: string;
  /** null = 룰 미매칭(임베딩/free_chat 폴백으로 넘어가는 케이스). */
  intent: Intent | null;
  slots: Slots;
}

// 정형 질문 14건 (8개 의도 + 폴백 + 슬롯 변형 포함).
const CASES: RuleCase[] = [
  // tournament_search — 대회 키워드 단독
  {
    msg: '서울 테니스 대회 알려줘',
    intent: 'tournament_search',
    slots: { region: 'seoul_metro', sport: 'tennis' },
  },
  // tournament_search — 종목 + 기간 슬롯
  {
    msg: '이번 주 풋살 대회 있어?',
    intent: 'tournament_search',
    slots: { sport: 'futsal', date_range: { from: '2026-06-01', to: '2026-06-07' } },
  },
  // tournament_detail — 대회 + 상세(신청) 키워드는 search 보다 우선
  {
    msg: '광주 테니스 대회 신청 방법 알려줘',
    intent: 'tournament_detail',
    slots: { region: 'gwangju', sport: 'tennis' },
  },
  // tournament_search — 대회 키워드가 my_profile 보다 우선
  {
    msg: '내 등급에 맞는 대회 추천해줘',
    intent: 'tournament_search',
    slots: {},
  },
  // tournament_search — 단일 날짜 슬롯 (월/일)
  {
    msg: '5/24 대회 뭐 있어',
    intent: 'tournament_search',
    slots: { date_range: { from: '2026-05-24', to: '2026-05-24' } },
  },
  // rule_lookup — '룰' 키워드
  {
    msg: '테니스 룰 알려줘',
    intent: 'rule_lookup',
    slots: { sport: 'tennis' },
  },
  // rule_lookup — '규칙' 키워드 (슬롯 없음)
  {
    msg: '타이브레이크 규칙이 궁금해',
    intent: 'rule_lookup',
    slots: {},
  },
  // venue_search — '풋살장' 키워드 + 종목 슬롯
  {
    msg: '근처 풋살장 어디 있어?',
    intent: 'venue_search',
    slots: { sport: 'futsal' },
  },
  // venue_search — '테니스장' 키워드 + 지역 슬롯
  {
    msg: '광주에 실내 테니스장 추천해줘',
    intent: 'venue_search',
    slots: { region: 'gwangju', sport: 'tennis' },
  },
  // club_search — '동호회' 키워드
  {
    msg: '동호회 가입하고 싶어',
    intent: 'club_search',
    slots: {},
  },
  // my_profile — '내 등급' (대회 키워드 없을 때만)
  {
    msg: '내 등급이 뭐야?',
    intent: 'my_profile',
    slots: {},
  },
  // match_schedule — '매치' + '일정/오늘' 동반
  {
    msg: '오늘 매치 일정 알려줘',
    intent: 'match_schedule',
    slots: { date_range: { from: '2026-06-07', to: '2026-06-07' } },
  },
  // free_chat 폴백 — 룰 미매칭
  {
    msg: '안녕하세요',
    intent: null,
    slots: {},
  },
  // free_chat 폴백 — 룰 미매칭
  {
    msg: '고마워요',
    intent: null,
    slots: {},
  },
];

Deno.test('classifyByRule: 14개 정형 질문이 기대 의도로 분류된다', () => {
  for (const c of CASES) {
    const hit = classifyByRule(c.msg);
    const got = hit?.intent ?? null;
    assertEquals(got, c.intent, `"${c.msg}" → ${got} (기대 ${c.intent})`);
  }
});

Deno.test('extractSlots: region/sport/date_range 가 정확히 추출된다', () => {
  for (const c of CASES) {
    const slots = extractSlots(c.msg, FIXED_NOW);
    assertEquals(slots, c.slots, `"${c.msg}" slots`);
  }
});

Deno.test('우선순위: 대회+상세는 detail, 대회+내등급은 search', () => {
  // tournament_detail 이 tournament_search 보다 먼저 매칭
  assertEquals(classifyByRule('대회 신청 어떻게 해')?.intent, 'tournament_detail');
  // 대회 키워드가 my_profile 키워드보다 우선
  assertEquals(classifyByRule('내 부수로 나갈 수 있는 대회 알려줘')?.intent, 'tournament_search');
});

Deno.test('match_schedule 은 일정 키워드 동반 시에만 매칭', () => {
  // '매치' 단독은 너무 광범위 → 룰 미매칭 (null)
  assertEquals(classifyByRule('매치'), null);
  // '매치' + 일정 키워드 → match_schedule
  assertEquals(classifyByRule('매치 일정 알려줘')?.intent, 'match_schedule');
});

Deno.test("'경기' 동음이의 false-positive 회피 (게임 vs 경기도)", () => {
  // '경기' 단독(시합 의미)은 region 으로 잡히면 안 됨
  assertEquals(extractSlots('경기 보러 갈래', FIXED_NOW).region, undefined);
  // '경기도'는 region 으로 매칭
  assertEquals(extractSlots('경기도 테니스 대회', FIXED_NOW).region, 'seoul_metro');
});

Deno.test('날짜 범위: 다음 주 > 이번 주말 > 이번 주 우선순위', () => {
  // 일요일(FIXED_NOW) 기준 이번 주 = 월~일
  assertEquals(extractDateRange('이번 주 대회', FIXED_NOW), {
    from: '2026-06-01',
    to: '2026-06-07',
  });
  // 다음 주 = 그 다음 월~일
  assertEquals(extractDateRange('다음 주 대회', FIXED_NOW), {
    from: '2026-06-08',
    to: '2026-06-14',
  });
});

Deno.test('routing 가능 여부: rule 분류 tournament_search 만 LLM 우회 대상', () => {
  // chat/index.ts 의 routing 조건 미러: intent ∈ {tournament_search} && confidence ≥ 0.95.
  // 룰 분류는 confidence 1.0 → tournament_search 면 routable.
  const wouldRoute = (r: IntentResult): boolean =>
    r.intent === 'tournament_search' && r.confidence >= 0.95;

  const routable: string[] = [];
  for (const c of CASES) {
    if (c.intent === null) continue;
    const hit = classifyByRule(c.msg)!;
    const result = buildRuleResult(hit, extractSlots(c.msg, FIXED_NOW));
    if (wouldRoute(result)) routable.push(c.msg);
  }

  // 14개 샘플 중 tournament_search 룰 매칭 4건만 LLM 없이 routing 된다.
  // (대회+상세 = tournament_detail 은 제외, 대회 키워드 단독만 routable)
  assertEquals(routable, [
    '서울 테니스 대회 알려줘',
    '이번 주 풋살 대회 있어?',
    '내 등급에 맞는 대회 추천해줘',
    '5/24 대회 뭐 있어',
  ]);
  assert(routable.length === 4);
});

Deno.test('UI 활성 종목은 메시지에 종목명이 없을 때 요청 종목으로 사용된다', () => {
  assertEquals(resolveRequestedSport(undefined, 'tennis'), {
    explicitSport: null,
    requestedSport: 'tennis',
  });
  assertEquals(resolveRequestedSport(undefined, 'futsal'), {
    explicitSport: null,
    requestedSport: 'futsal',
  });
});

Deno.test('메시지에 명시된 종목은 UI 활성 종목보다 우선한다', () => {
  assertEquals(resolveRequestedSport('tennis', 'futsal'), {
    explicitSport: 'tennis',
    requestedSport: 'tennis',
  });
});
