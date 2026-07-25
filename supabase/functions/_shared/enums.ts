// 정본은 DB `sport` enum. 타입을 배열에서 파생시켜, 종목이 늘 때 리터럴 유니온을
// 여기저기 다시 적는 일이 없게 한다(JY-146).
export const SPORTS = ['tennis', 'futsal'] as const;
export type Sport = typeof SPORTS[number];

export function isValidSport(value: unknown): value is Sport {
  return typeof value === 'string' && (SPORTS as readonly string[]).includes(value);
}

// 등급 정본은 DB public.grades 다(JY-146 P3-a). Edge 는 TS 사본을 두지 않는다 — 사본이 있으면
// 관리자가 grades 에 등급을 추가했을 때 Flutter 는 선택지에 띄우는데 Edge 만 400 으로 거부하고
// 라벨 대신 코드를 노출한다(#319). 검증·표시가 필요한 지점에서 grades 를 직접 읽는다.

// =========================
// Tennis Org (협회·조직)
// =========================
export const TENNIS_ORGS = [
  'kta',
  'kato',
  'kata',
  'ktfs',
  'kstf',
  'kssta',
  'kasta',
  'gj',
  'jn',
  'local',
] as const;

export type TennisOrg = typeof TENNIS_ORGS[number];

export const TENNIS_ORG_LABELS: Record<TennisOrg, string> = {
  kta: '대한테니스협회 (KTA)',
  kato: '한국테니스발전협의회 (KATO)',
  kata: '한국동호인테니스협회 (KATA)',
  ktfs: '국민생활체육 전국테니스연합회 (KTFS)',
  kstf: '한국시니어테니스연맹 (KSTF, 60+)',
  kssta: '한국슈퍼시니어테니스협회 (KSSTA)',
  kasta: '단식 테니스 (KASTA / 단테매)',
  gj: '광주광역시테니스협회 (GJTA)',
  jn: '전라남도테니스협회 (JNTA)',
  local: '시·군 또는 클럽 자체',
};

export function isValidTennisOrg(value: string): value is TennisOrg {
  return (TENNIS_ORGS as readonly string[]).includes(value);
}

// =========================
// Region (권역)
// =========================
// 표준 17개 광역시도. Dart grade_labels.dart regionCodes / seed.sql regions 와 코드·순서 1:1.
// deprecated 묶음 코드(seoul_metro 등)는 여기서 제외 — 신규 저장은 시도 코드만 사용한다.
export const REGION_CODES = [
  'seoul',
  'gyeonggi',
  'incheon',
  'gangwon',
  'daejeon',
  'sejong',
  'chungbuk',
  'chungnam',
  'gwangju',
  'jeonbuk',
  'jeonnam',
  'busan',
  'ulsan',
  'daegu',
  'gyeongbuk',
  'gyeongnam',
  'jeju',
] as const;

export type RegionCode = typeof REGION_CODES[number];

export const REGION_LABELS: Record<RegionCode, string> = {
  seoul: '서울',
  gyeonggi: '경기',
  incheon: '인천',
  gangwon: '강원',
  daejeon: '대전',
  sejong: '세종',
  chungbuk: '충북',
  chungnam: '충남',
  gwangju: '광주',
  jeonbuk: '전북',
  jeonnam: '전남',
  busan: '부산',
  ulsan: '울산',
  daegu: '대구',
  gyeongbuk: '경북',
  gyeongnam: '경남',
  jeju: '제주',
};

export function isValidRegionCode(value: string): value is RegionCode {
  return (REGION_CODES as readonly string[]).includes(value);
}

// 한글 권역명(REGION_LABELS) → RegionCode 역매핑.
const REGION_CODE_BY_LABEL: Record<string, RegionCode> = Object.fromEntries(
  (Object.entries(REGION_LABELS) as Array<[RegionCode, string]>).map(
    ([code, label]) => [label, code],
  ),
) as Record<string, RegionCode>;

/** 한글 권역명(예: '광주')을 RegionCode('gwangju')로 변환. 미매칭/빈값이면 null. */
export function regionCodeFromLabel(
  label: string | null | undefined,
): RegionCode | null {
  if (!label) return null;
  return REGION_CODE_BY_LABEL[label.trim()] ?? null;
}

// =========================
// EntryFeeUnit
// =========================
export const ENTRY_FEE_UNITS = ['per_team', 'per_person'] as const;
export type EntryFeeUnit = typeof ENTRY_FEE_UNITS[number];

export function isValidEntryFeeUnit(value: string): value is EntryFeeUnit {
  return (ENTRY_FEE_UNITS as readonly string[]).includes(value);
}

// =========================
// Recruiting status — 모집상태 서버 필터 (RPC p_recruiting)
// =========================

export const RECRUITING_STATES = ['open', 'closed'] as const;
export type RecruitingState = typeof RECRUITING_STATES[number];

/**
 * 모집상태 쿼리 파라미터 정규화.
 * 'open' | 'closed' 만 허용하고, 그 외(빈값/오타/null/undefined)는 null 로 반환한다.
 * null = RPC p_recruiting NULL = 필터 미적용.
 */
export function parseRecruiting(raw: unknown): RecruitingState | null {
  if (typeof raw !== 'string') return null;
  return (RECRUITING_STATES as readonly string[]).includes(raw) ? (raw as RecruitingState) : null;
}

// =========================
// Tennis Divisions — 부서 코드({org}_{suffix}) 형식 검증
// 부서 카탈로그 정본은 DB public.tennis_divisions 다. Edge 는 목록이 필요 없고
// 형식 검증만 하므로 사본을 두지 않는다(JY-146 P2).
// =========================

/** Division code 형식 검증: 영문소문자/숫자/언더스코어만 (^[a-z0-9_]+$). */
const DIVISION_CODE_PATTERN = /^[a-z0-9_]+$/;

/**
 * 쉼표구분 division_codes 문자열을 파싱한다.
 *   "gj_m_gold, jn_m_gold ,bad code" → ['gj_m_gold', 'jn_m_gold']
 * 처리: split(',') → trim → 빈값 제거 → 형식(^[a-z0-9_]+$) 불일치 제거.
 * 결과가 비면 null (RPC 의 p_division_codes NULL = 필터 미적용).
 *
 * 형식 sanitize 만 수행한다. 실제 SQL 인젝션 방지는 RPC 파라미터 바인딩이 담당하고,
 * 코드 화이트리스트는 종류가 많아(69+) 유지보수 부담이 커 형식 체크로 충분하다.
 */
export function parseDivisionCodes(raw: string | null | undefined): string[] | null {
  if (!raw) return null;
  const codes = raw
    .split(',')
    .map((c) => c.trim())
    .filter((c) => c.length > 0 && DIVISION_CODE_PATTERN.test(c));
  return codes.length > 0 ? codes : null;
}

// 광주/전남 사이트 텍스트 키워드 → division suffix 매핑 (크롤러용)
// prefix(gj_ / jn_)는 호출부에서 붙임
export const GJ_KEYWORD_TO_SUFFIX: Array<{ keywords: string[]; suffix: string }> = [
  { keywords: ['오픈부', '남자오픈', '오픈'], suffix: 'm_open' },
  { keywords: ['골드부', '골드'], suffix: 'm_gold' },
  { keywords: ['남자일반부', '일반부', '남자일반'], suffix: 'm_general' },
  { keywords: ['지도자부', '지도자'], suffix: 'm_instructor' },
  { keywords: ['마스터즈부', '마스터즈'], suffix: 'm_masters' },
  { keywords: ['남자신인부', '신인부', '신인'], suffix: 'm_rookie' },
  { keywords: ['베테랑부', '베테랑'], suffix: 'm_veteran' },
  { keywords: ['초급자부', '비입상자부', '초급자'], suffix: 'm_beginner' },
  { keywords: ['여자오픈부', '여자오픈'], suffix: 'w_open' },
  { keywords: ['우승자부', '여자우승자', '국화', '금배'], suffix: 'w_winner' },
  { keywords: ['여자신인부', '여자신인'], suffix: 'w_rookie' },
  { keywords: ['부부부', '부부'], suffix: 'couple' },
  { keywords: ['크로스'], suffix: 'cross' },
];

/**
 * 등급 코드 유효성. 활성 등급 목록(`activeGrades`)은 호출부가 DB 에서 읽어 넘긴다 —
 *   select code from public.grades where sport = ? and is_active
 * 목록을 인자로 받는 이유: enums.ts 를 순수 모듈로 유지(DB 클라이언트 의존 없음)하고,
 * 호출부가 조회 실패를 자기 방식(503 등)으로 처리하게 한다.
 *
 * 테니스는 등급 코드 외에 **부서 코드**(gj_m_gold 등)도 자격 표기로 쓴다. 부서 정본은
 * DB public.tennis_divisions 고 Edge 는 형식만 본다(parseDivisionCodes 와 동일 규칙).
 */
export function isValidGrade(
  sport: Sport,
  grade: string,
  activeGrades: ReadonlySet<string>,
): boolean {
  if (activeGrades.has(grade)) return true;
  return sport === 'tennis' && isValidDivisionCode(grade);
}

/** Division code 유효성: {org}_{suffix} 패턴 (예: gj_m_gold, kta_m_open) */
function isValidDivisionCode(code: string): boolean {
  const idx = code.indexOf('_');
  if (idx < 1) return false;
  const org = code.substring(0, idx);
  return (TENNIS_ORGS as readonly string[]).includes(org);
}

// 삭제(#319): canEnter(= eligibleGrades.includes, 호출부 없음 — 자격 판정 정본은 DB RPC),
// rankOf(등급 순서 정본은 grades.sort_order, 호출부 없음), GRADE_LABELS(grades.label_ko 사본).

export const SPORT_LABELS: Record<Sport, string> = {
  tennis: '테니스',
  futsal: '풋살',
};

// =========================
// Player Origin (선수 출신 단계)
// =========================
export const PLAYER_ORIGINS = [
  'elementary',
  'middle',
  'high',
  'university',
  'professional',
  'instructor',
] as const;
export type PlayerOrigin = typeof PLAYER_ORIGINS[number];

export const PLAYER_ORIGIN_LABELS: Record<PlayerOrigin, string> = {
  elementary: '초등 선수 출신',
  middle: '중등 선수 출신',
  high: '고등 선수 출신',
  university: '대학 선수 출신',
  professional: '실업 선수 출신',
  instructor: '지도자',
};

export function isValidPlayerOrigin(value: string): value is PlayerOrigin {
  return (PLAYER_ORIGINS as readonly string[]).includes(value);
}
