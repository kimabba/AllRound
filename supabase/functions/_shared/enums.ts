// 정본은 DB `sport` enum. 타입을 배열에서 파생시켜, 종목이 늘 때 리터럴 유니온을
// 여기저기 다시 적는 일이 없게 한다(JY-146).
export const SPORTS = ['tennis', 'futsal'] as const;
export type Sport = typeof SPORTS[number];

export function isValidSport(value: unknown): value is Sport {
  return typeof value === 'string' && (SPORTS as readonly string[]).includes(value);
}

export const TENNIS_GRADES = ['under1y', 'y1to3', 'y3to5', 'over5y'] as const;
export const FUTSAL_GRADES = ['intro', 'beginner', 'intermediate', 'advanced', 'elite'] as const;

export type TennisGrade = typeof TENNIS_GRADES[number];
export type FutsalGrade = typeof FUTSAL_GRADES[number];
export type Grade = TennisGrade | FutsalGrade;

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

const TENNIS_RANK: Record<TennisGrade, number> = {
  under1y: 0,
  y1to3: 1,
  y3to5: 2,
  over5y: 3,
};

const FUTSAL_RANK: Record<FutsalGrade, number> = {
  intro: 0,
  beginner: 1,
  intermediate: 2,
  advanced: 3,
  elite: 4,
};

export function isValidGrade(sport: Sport, grade: string): grade is Grade {
  if (sport === 'tennis') {
    // Legacy grade (y1to3 등) 또는 division code (gj_m_gold 등) 모두 허용
    if ((TENNIS_GRADES as readonly string[]).includes(grade)) return true;
    return isValidDivisionCode(grade);
  }
  return (FUTSAL_GRADES as readonly string[]).includes(grade);
}

/** Division code 유효성: {org}_{suffix} 패턴 (예: gj_m_gold, kta_m_open) */
function isValidDivisionCode(code: string): boolean {
  const idx = code.indexOf('_');
  if (idx < 1) return false;
  const org = code.substring(0, idx);
  return (TENNIS_ORGS as readonly string[]).includes(org);
}

/**
 * 사용자 등급 기준으로 출전 가능한 등급 배열을 반환.
 * 테니스는 "본인 등급보다 같거나 낮은 부수의 대회 = 출전 가능"으로 가정한다.
 *   (실제 동호인 룰에서는 1부 사람이 5부 대회 못 나가는 경우도 있으나
 *    MVP에서는 "낮은 부수=상위" 가정 하에 본인 등급 또는 그 이하 등급 대회 모두 출전 가능으로 처리)
 *
 * 즉 사용자가 'div3' 이면 출전 가능한 eligible_grades 는
 *   div5, div4, div3, rookie  (본인보다 등급이 낮거나 같은) — 사용자가 div3이면 div3 이상 대회는 부담스러움
 *
 * 사실 동호인 테니스는 "내 부수 또는 그 위 부수"가 출전 가능.
 *   예: 내가 3부 → 3부, 4부, 5부, 신입 대회 출전 가능 (낮은 부수 = 더 잘함, 상위 부수)
 *   여기서 'div1' 이 가장 잘하는 사람.
 *   대회의 eligible_grades 에는 "참가 자격이 되는 등급들"이 들어 있음.
 *
 * 따라서 단순 매칭: 사용자 grade ∈ eligible_grades.
 * 이 함수는 명시적 "이 사용자가 해당 대회에 나갈 수 있는가" 체크용.
 */
export function canEnter(userGrade: string, eligibleGrades: string[]): boolean {
  return eligibleGrades.includes(userGrade);
}

/**
 * UI 표시명 매핑
 */
export const GRADE_LABELS: Record<string, string> = {
  under1y: '1년 미만',
  y1to3: '1~3년',
  y3to5: '3~5년',
  over5y: '5년 이상',
  intro: '입문',
  beginner: '초급',
  intermediate: '중급',
  advanced: '고급',
  elite: '선출',
};

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

export function rankOf(sport: Sport, grade: string): number | null {
  if (sport === 'tennis' && grade in TENNIS_RANK) return TENNIS_RANK[grade as TennisGrade];
  if (sport === 'futsal' && grade in FUTSAL_RANK) return FUTSAL_RANK[grade as FutsalGrade];
  return null;
}
