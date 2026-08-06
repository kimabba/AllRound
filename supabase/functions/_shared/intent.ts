/**
 * Intent classifier shared module (Day 3-4, shadow mode).
 *
 * 구조:
 *   1. 룰 기반 1차 분류 (정규식 + 키워드) — `classifyByRule`
 *   2. 임베딩 기반 KNN 폴백 — chat/index.ts 에서 RPC `intent_classify` 호출
 *   3. 둘 다 실패 시 free_chat 폴백
 *
 * 슬롯 추출 (`extractSlots`) 은 의도와 독립적으로 항상 시도.
 *   - region: 한국어 별칭 → REGION_CODES
 *   - sport:  한국어/영어 키워드 → Sport
 *   - date_range: 한국어 자연어 → ISO 8601 (KST/Asia/Seoul 기준)
 *
 * 주의: 이 모듈은 한국어 동호인 도메인 한정. 다국어 확장 시 별도 모듈로 분리.
 *
 * 라우팅 상태 (JY-107 확정):
 *   - 룰 분류(confidence=1.0): 실제 라우팅 활성 — ROUTABLE_INTENTS 에 대해 검색 실행.
 *   - 임베딩 분류: shadow-only. 관측(SSE/메트릭)만 하고 라우팅은 안 한다.
 *     실측상 similarity 상한이 ~0.86 < 라우팅 게이트 0.95 라 구조적으로 라우팅에 미도달.
 *     시드 품질(intent 당 7개, leave-one-out 정확도 67%, 오분류 similarity 가 정확분류보다
 *     높음) 개선 전까지 임베딩 라우팅은 켜지 않는다. 상세는 chat/types.ts 게이트 주석 참고.
 */

import { REGION_CODES, type RegionCode, type Sport } from './enums.ts';

// =========================
// 타입
// =========================
export type Intent =
  | 'tournament_search'
  | 'tournament_detail'
  | 'club_search'
  | 'rule_lookup'
  | 'venue_search'
  | 'match_schedule'
  | 'my_profile'
  | 'free_chat';

export const INTENT_VALUES: readonly Intent[] = [
  'tournament_search',
  'tournament_detail',
  'club_search',
  'rule_lookup',
  'venue_search',
  'match_schedule',
  'my_profile',
  'free_chat',
] as const;

export interface DateRange {
  /** ISO 8601 date (YYYY-MM-DD), KST 기준 포함 시작일. */
  from: string;
  /** ISO 8601 date (YYYY-MM-DD), KST 기준 포함 종료일. */
  to: string;
}

export interface Slots {
  region?: RegionCode;
  sport?: Sport;
  date_range?: DateRange;
}

export type IntentMethod = 'rule' | 'embedding' | 'fallback';

export interface IntentResult {
  intent: Intent;
  /** 0..1. 룰 매칭 시 1.0, 임베딩 시 cosine similarity, 폴백 시 0. */
  confidence: number;
  method: IntentMethod;
  slots: Slots;
  /** 디버깅용 — 어떤 룰이 매치했는지 (룰 분류 시에만). */
  rule_matched?: string;
}

export interface RuleClassification {
  intent: Intent;
  rule: string;
}

// =========================
// 지역 별칭 매핑
// =========================
// 사용자가 흔히 쓰는 한국어 표현 → REGION_CODES.
// REGION_CODES 변경 시 이 맵도 동기 유지 필요.
// 주의: 동음/부분 매칭 false-positive 회피.
//   - '경기' 는 "경기도" (region) 와 "경기" (match/game) 가 동음 → 경기도/경기지역 같은 명시 표현만 채택.
//   - '경남'/'경북' 도 유사 위험이 있으나 동호인 도메인에서 단독 사용 빈도 낮음.
// 표준 17개 광역시도. '경기' 단독은 시합(경기) 동음이의라 '경기도|경기 지역'만 매칭.
const REGION_ALIASES: ReadonlyArray<{ pattern: RegExp; code: RegionCode }> = [
  { pattern: /(서울특별시|서울시|서울)/, code: 'seoul' },
  { pattern: /(경기도|경기\s*지역)/, code: 'gyeonggi' },
  { pattern: /(인천광역시|인천시|인천)/, code: 'incheon' },
  { pattern: /(강원특별자치도|강원도|강원)/, code: 'gangwon' },
  { pattern: /(대전광역시|대전시|대전)/, code: 'daejeon' },
  { pattern: /(세종특별자치시|세종시|세종)/, code: 'sejong' },
  { pattern: /(충청북도|충북)/, code: 'chungbuk' },
  { pattern: /(충청남도|충남)/, code: 'chungnam' },
  { pattern: /(광주광역시|광주시|광주)/, code: 'gwangju' },
  { pattern: /(전라북도|전북)/, code: 'jeonbuk' },
  { pattern: /(전라남도|전남)/, code: 'jeonnam' },
  { pattern: /(부산광역시|부산시|부산)/, code: 'busan' },
  { pattern: /(울산광역시|울산시|울산)/, code: 'ulsan' },
  { pattern: /(대구광역시|대구시|대구)/, code: 'daegu' },
  { pattern: /(경상북도|경북)/, code: 'gyeongbuk' },
  { pattern: /(경상남도|경남)/, code: 'gyeongnam' },
  { pattern: /(제주특별자치도|제주도|제주)/, code: 'jeju' },
];

// 영문 region code 자체가 메시지에 등장한 경우 그대로 채택.
function regionFromDirectCode(text: string): RegionCode | undefined {
  for (const code of REGION_CODES) {
    // 단어 경계 매칭 (영문/숫자만)
    const re = new RegExp(`\\b${code}\\b`, 'i');
    if (re.test(text)) return code;
  }
  return undefined;
}

function extractRegion(text: string): RegionCode | undefined {
  const direct = regionFromDirectCode(text);
  if (direct) return direct;
  for (const { pattern, code } of REGION_ALIASES) {
    if (pattern.test(text)) return code;
  }
  return undefined;
}

// =========================
// 종목 별칭
// =========================
function extractSport(text: string): Sport | undefined {
  if (/(테니스|tennis)/i.test(text)) return 'tennis';
  if (/(풋살|futsal)/i.test(text)) return 'futsal';
  return undefined;
}

// =========================
// 날짜 범위 (KST / Asia/Seoul)
// =========================
// Deno Edge runtime 은 시스템 TZ 가 UTC. 명시적으로 KST 오프셋 (+09:00) 으로 계산.
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** 현재 시각 기준 KST 의 "오늘" 자정 (Date 객체, UTC 내부 표현). */
function kstToday(now: Date = new Date()): Date {
  // KST 시각의 자정을 UTC Date 로 표현: (UTC ms + KST offset) → 자정 절단 → KST offset 빼서 UTC ms 로 환원
  const kstMs = now.getTime() + KST_OFFSET_MS;
  const kstMidnight = Math.floor(kstMs / 86_400_000) * 86_400_000;
  return new Date(kstMidnight - KST_OFFSET_MS);
}

/** KST 자정 Date → 'YYYY-MM-DD' (KST 날짜). */
function formatKstDate(d: Date): string {
  const kst = new Date(d.getTime() + KST_OFFSET_MS);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const day = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** KST 기준 day 단위 가감. */
function addDays(d: Date, days: number): Date {
  return new Date(d.getTime() + days * 86_400_000);
}

/** KST 기준 요일 (0=일 ~ 6=토). 한국 통념의 "이번 주 = 월~일" 계산에 사용. */
function kstDayOfWeek(d: Date): number {
  const kst = new Date(d.getTime() + KST_OFFSET_MS);
  return kst.getUTCDay();
}

/** "이번 주" = 가장 가까운 과거(또는 당일) 월요일 ~ 그 주 일요일. */
function thisWeekRange(today: Date): DateRange {
  const dow = kstDayOfWeek(today); // 0=일, 1=월, ..., 6=토
  // 월요일까지 거슬러 올라가는 일수. 일요일이면 6일 전, 월요일이면 0일.
  const daysToMonday = dow === 0 ? 6 : dow - 1;
  const monday = addDays(today, -daysToMonday);
  const sunday = addDays(monday, 6);
  return { from: formatKstDate(monday), to: formatKstDate(sunday) };
}

function thisWeekendRange(today: Date): DateRange {
  // 이번 주의 토요일 ~ 일요일.
  const dow = kstDayOfWeek(today);
  const daysToSaturday = (6 - dow + 7) % 7; // 토요일까지의 일수
  // 단 오늘이 일요일이면 "이번 주말" 은 어제 토 ~ 오늘 일 로 해석.
  let saturday: Date;
  if (dow === 0) {
    saturday = addDays(today, -1);
  } else {
    saturday = addDays(today, daysToSaturday);
  }
  const sunday = addDays(saturday, 1);
  return { from: formatKstDate(saturday), to: formatKstDate(sunday) };
}

function nextWeekRange(today: Date): DateRange {
  const thisWeek = thisWeekRange(today);
  const nextMonday = addDays(new Date(thisWeek.from + 'T00:00:00+09:00'), 7);
  const nextSunday = addDays(nextMonday, 6);
  return { from: formatKstDate(nextMonday), to: formatKstDate(nextSunday) };
}

/** "5월", "1월" 등 단독 월 → 현재 KST 연도의 해당 월 전체. */
function monthRange(today: Date, month: number): DateRange {
  const kst = new Date(today.getTime() + KST_OFFSET_MS);
  const year = kst.getUTCFullYear();
  const first = new Date(Date.UTC(year, month - 1, 1) - KST_OFFSET_MS);
  // 다음 달 1일 - 1일.
  const lastUtc = new Date(Date.UTC(year, month, 1) - KST_OFFSET_MS);
  const last = addDays(lastUtc, -1);
  return { from: formatKstDate(first), to: formatKstDate(last) };
}

/** "다음 달" → 다음 달 전체. Date.UTC 가 12→1월 연도 넘어감을 자동 처리. */
function nextMonthRange(today: Date): DateRange {
  const kst = new Date(today.getTime() + KST_OFFSET_MS);
  const year = kst.getUTCFullYear();
  const month0 = kst.getUTCMonth(); // 0-based 현재 월
  const first = new Date(Date.UTC(year, month0 + 1, 1) - KST_OFFSET_MS);
  const lastUtc = new Date(Date.UTC(year, month0 + 2, 1) - KST_OFFSET_MS);
  const last = addDays(lastUtc, -1);
  return { from: formatKstDate(first), to: formatKstDate(last) };
}

/** "5/24", "5월 24일" 등 단일 날짜 → 그 날 하루. */
function singleDayRange(today: Date, month: number, day: number): DateRange {
  const kst = new Date(today.getTime() + KST_OFFSET_MS);
  const year = kst.getUTCFullYear();
  const d = new Date(Date.UTC(year, month - 1, day) - KST_OFFSET_MS);
  const iso = formatKstDate(d);
  return { from: iso, to: iso };
}

/**
 * 날짜 범위 추출. 첫 매칭 우선.
 * 매칭 순서가 결과에 영향 — 더 구체적인 패턴 (단일 날짜) 을 먼저, 광범위 (이번 주) 를 나중에.
 */
export function extractDateRange(text: string, now: Date = new Date()): DateRange | undefined {
  const today = kstToday(now);

  // "5/24", "5-24" — 구체적 단일 날짜
  const slashMatch = text.match(/\b(\d{1,2})[\/\-](\d{1,2})\b/);
  if (slashMatch) {
    const month = parseInt(slashMatch[1], 10);
    const day = parseInt(slashMatch[2], 10);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return singleDayRange(today, month, day);
    }
  }

  // "5월 24일", "5월24일"
  const koreanDateMatch = text.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/);
  if (koreanDateMatch) {
    const month = parseInt(koreanDateMatch[1], 10);
    const day = parseInt(koreanDateMatch[2], 10);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return singleDayRange(today, month, day);
    }
  }

  // "다음 주" — "이번 주" 보다 먼저 검사 (substring 충돌 방지)
  if (/다음\s*주/.test(text)) {
    return nextWeekRange(today);
  }

  // "이번 주말" — "이번 주" 보다 먼저
  if (/이번\s*주말|주말/.test(text)) {
    return thisWeekendRange(today);
  }

  if (/이번\s*주|금주/.test(text)) {
    return thisWeekRange(today);
  }

  if (/내일/.test(text)) {
    const tomorrow = addDays(today, 1);
    const iso = formatKstDate(tomorrow);
    return { from: iso, to: iso };
  }

  if (/오늘|금일/.test(text)) {
    const iso = formatKstDate(today);
    return { from: iso, to: iso };
  }

  // "다음 달" / "담달" / "익월" — "이번 달" 보다 먼저 (substring 충돌 방지).
  if (/다음\s*달|담달|익월/.test(text)) {
    return nextMonthRange(today);
  }

  // "이번 달" / "금월" — 현재 KST 월 전체.
  if (/이번\s*달|금월/.test(text)) {
    const kst = new Date(today.getTime() + KST_OFFSET_MS);
    return monthRange(today, kst.getUTCMonth() + 1);
  }

  // "5월", "12월" 단독 — "5월 24일" 패턴이 위에서 잡혔으면 도달 안 함.
  const monthOnly = text.match(/(\d{1,2})\s*월(?!\s*\d)/);
  if (monthOnly) {
    const month = parseInt(monthOnly[1], 10);
    if (month >= 1 && month <= 12) {
      return monthRange(today, month);
    }
  }

  // "올해" / "금년" — 올해 남은 기간(오늘 ~ 연말). "몇 개 남았어" 류 질문에서 지난 대회
  // 제외. 구체 월("올해 5월")이 함께면 위 monthOnly 가 먼저 잡아 더 좁은 범위 우선.
  if (/올해|올\s*한\s*해|금년/.test(text)) {
    const kst = new Date(today.getTime() + KST_OFFSET_MS);
    const year = kst.getUTCFullYear();
    const yearEnd = new Date(Date.UTC(year, 11, 31) - KST_OFFSET_MS);
    return { from: formatKstDate(today), to: formatKstDate(yearEnd) };
  }

  return undefined;
}

// =========================
// 슬롯 추출 진입점
// =========================
export function extractSlots(text: string, now: Date = new Date()): Slots {
  const slots: Slots = {};
  const region = extractRegion(text);
  if (region) slots.region = region;
  const sport = extractSport(text);
  if (sport) slots.sport = sport;
  const dateRange = extractDateRange(text, now);
  if (dateRange) slots.date_range = dateRange;
  return slots;
}

// =========================
// 룰 기반 분류
// =========================
// 첫 매칭 우선 (specific → generic). 매칭된 룰의 이름을 함께 반환해 디버깅에 활용.
//
// 매칭 정확도가 부족한 케이스는 의도적으로 null 반환 → 임베딩/폴백으로 넘김.
// 카테고리 정확도 < 룰 누락 (recall) 우선 — false positive 보다 false negative 가 안전.
// "장배" 는 회장배·협회장배·시장배·구청장배·이사장배·위원장배 등 "~장배" 대회명을 모두 커버.
// "회장기·협회장기·장관기" 는 "~기" 대회명 (단독 "기" 는 false positive 과다 → 한정).
// recall 우선 정책상 "성장배경" 등 드문 오매칭은 감수 (false negative > false positive 회피).
const TOURNAMENT_KW = /(대회|토너먼트|시합|컵|오픈|선수권|장배|회장기|협회장기|장관기|왕중왕전)/;
const CLUB_KW = /(클럽|동호회|동호인\s*모임)/;
const RULE_KW = /(룰|규칙|규정|규약|룰북)/;
const VENUE_KW = /(구장|풋살장|테니스장|경기장|연습장|코트|체육관|실내.*장|실외.*장)/;
const MATCH_KW = /(매치|경기|시합\s*일정)/;
const SCHEDULE_KW = /(일정|스케줄|언제|오늘|내일|이번\s*주|다음\s*주)/;
const DETAIL_KW = /(자세|상세|어떻게|신청|참가\s*방법|등록\s*방법|접수)/;
const SEARCH_KW = /(검색|찾|알려|뭐\s*있|있어|있나|추천|보여)/;
const MY_PROFILE_KW = /(내\s*(등급|점수|협회|프로필|랭킹|부수)|제\s*(등급|점수|협회|프로필|부수))/;
// "클럽 만들기/개설/창단" 은 기존 클럽 검색이 아니다 → club_search 룰에서 제외해 폴백(임베딩)으로.
const CREATE_KW = /(만들|만드는|개설|창단|창설)/;

export function classifyByRule(text: string): RuleClassification | null {
  // 1. tournament_detail — 대회 + 상세 키워드 (my_profile보다 먼저: "내 등급 대회 신청방법")
  if (TOURNAMENT_KW.test(text) && DETAIL_KW.test(text)) {
    return { intent: 'tournament_detail', rule: 'tournament_with_detail' };
  }

  // 2. rule_lookup — 룰/규칙/규정 키워드는 tournament_search 보다 먼저.
  //    "대회 참가 자격 규정" 처럼 '대회'가 있어도 규정 질문은 검색이 아니라 룰 조회다.
  if (RULE_KW.test(text)) {
    return { intent: 'rule_lookup', rule: 'rule_keyword' };
  }

  // 3. tournament_search — 대회 키워드 (my_profile보다 먼저: "내 등급에 맞는 대회 알려줘")
  if (TOURNAMENT_KW.test(text)) {
    return { intent: 'tournament_search', rule: 'tournament_keyword' };
  }

  // 4. my_profile — 대회 키워드 없을 때만 ("내 등급이 뭐야", "내 협회 알려줘")
  if (MY_PROFILE_KW.test(text)) {
    return { intent: 'my_profile', rule: 'my_profile_keyword' };
  }

  // 5. venue_search — 구장/풋살장/테니스장 키워드
  if (VENUE_KW.test(text)) {
    return { intent: 'venue_search', rule: 'venue_keyword' };
  }

  // 6. club_search — 클럽 키워드 (단, "만들기/개설" 은 생성 의도 → 제외해 폴백으로)
  if (CLUB_KW.test(text) && !CREATE_KW.test(text)) {
    return { intent: 'club_search', rule: 'club_keyword' };
  }

  // 6. match_schedule — "매치/경기" + (일정/시간 키워드)
  //    "매치" 단독은 광범위 → 일정 키워드 동반 시에만 매칭.
  if (MATCH_KW.test(text) && SCHEDULE_KW.test(text)) {
    return { intent: 'match_schedule', rule: 'match_with_schedule' };
  }

  // 7. 그 외 검색 동사 단독 ("뭐 있어", "알려줘") 은 너무 광범위 → 룰 매칭 실패 처리.
  void SEARCH_KW; // referenced for future use; intentionally not matched standalone
  return null;
}

// =========================
// 임베딩 분류 결과 처리 헬퍼
// =========================
// chat/index.ts 에서 RPC `intent_classify` 호출 결과를 IntentResult 로 변환할 때 사용.
export function buildEmbeddingResult(
  intent: Intent,
  similarity: number,
  slots: Slots,
): IntentResult {
  return {
    intent,
    confidence: Math.max(0, Math.min(1, similarity)),
    method: 'embedding',
    slots,
  };
}

export function buildRuleResult(
  rule: RuleClassification,
  slots: Slots,
): IntentResult {
  return {
    intent: rule.intent,
    confidence: 1,
    method: 'rule',
    slots,
    rule_matched: rule.rule,
  };
}

export function buildFallbackResult(slots: Slots): IntentResult {
  return {
    intent: 'free_chat',
    confidence: 0,
    method: 'fallback',
    slots,
  };
}

type SportSlot = NonNullable<Slots['sport']>;

export interface RequestedSportResolution {
  explicitSport: SportSlot | null;
  requestedSport: SportSlot | null;
}

function normalizeSportSlot(sport: string | undefined | null): SportSlot | null {
  if (sport === 'tennis' || sport === 'futsal') return sport;
  return null;
}

export function resolveRequestedSport(
  explicitSport: string | undefined | null,
  clientActiveSport: string | undefined | null,
): RequestedSportResolution {
  const normalizedExplicitSport = normalizeSportSlot(explicitSport);
  const normalizedActiveSport = normalizeSportSlot(clientActiveSport);
  return {
    explicitSport: normalizedExplicitSport,
    requestedSport: normalizedExplicitSport ?? normalizedActiveSport,
  };
}
