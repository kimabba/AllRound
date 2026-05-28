export type Sport = 'tennis' | 'futsal';

export const TENNIS_GRADES = ['under1y', 'y1to3', 'y3to5', 'over5y'] as const;
export const FUTSAL_GRADES = ['beginner', 'intermediate', 'advanced'] as const;

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
export const REGION_CODES = [
  'gwangju',
  'jeonnam',
  'seoul_metro',
  'busan_ulsan_gn',
  'daegu_gb',
  'chungcheong',
  'gangwon',
  'jeju',
] as const;

export type RegionCode = typeof REGION_CODES[number];

export const REGION_LABELS: Record<RegionCode, string> = {
  gwangju: '광주',
  jeonnam: '전남',
  seoul_metro: '수도권',
  busan_ulsan_gn: '부산·울산·경남',
  daegu_gb: '대구·경북',
  chungcheong: '충청',
  gangwon: '강원',
  jeju: '제주',
};

export function isValidRegionCode(value: string): value is RegionCode {
  return (REGION_CODES as readonly string[]).includes(value);
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
// Tennis Divisions — 협회별 부서 코드 ({org}_{div} 형식)
// tournaments.eligible_grades 에 저장되는 값
// =========================

export interface TennisDivisionDef {
  code: string;
  org: string;
  label: string;
  hasRanking?: boolean;
  gender?: 'male' | 'female' | 'mixed' | 'all';
}

export const TENNIS_DIVISIONS: TennisDivisionDef[] = [
  // 광주광역시 (gj) — 남자 랭킹 배점 부서
  { code: 'gj_m_open', org: 'gj', label: '오픈부', hasRanking: true, gender: 'male' },
  { code: 'gj_m_gold', org: 'gj', label: '골드부', hasRanking: true, gender: 'male' },
  { code: 'gj_m_general', org: 'gj', label: '일반부', hasRanking: true, gender: 'male' },
  { code: 'gj_m_instructor', org: 'gj', label: '지도자부', hasRanking: true, gender: 'male' },
  // 광주 — 남자 선택 부서
  { code: 'gj_m_masters', org: 'gj', label: '마스터즈부', hasRanking: false, gender: 'male' },
  { code: 'gj_m_rookie', org: 'gj', label: '신인부', hasRanking: false, gender: 'male' },
  { code: 'gj_m_veteran', org: 'gj', label: '베테랑부', hasRanking: false, gender: 'male' },
  { code: 'gj_m_beginner', org: 'gj', label: '초급자부', hasRanking: false, gender: 'male' },
  // 광주 — 여자
  { code: 'gj_w_open', org: 'gj', label: '여자오픈부', hasRanking: false, gender: 'female' },
  { code: 'gj_w_winner', org: 'gj', label: '여자우승자부', hasRanking: true, gender: 'female' },
  { code: 'gj_w_rookie', org: 'gj', label: '여자신인부', hasRanking: true, gender: 'female' },
  // 광주 — 혼성
  { code: 'gj_couple', org: 'gj', label: '부부부', hasRanking: false, gender: 'mixed' },
  { code: 'gj_cross', org: 'gj', label: '크로스대회', hasRanking: false, gender: 'mixed' },

  // 전라남도 (jn) — gj와 동일 체계
  { code: 'jn_m_open', org: 'jn', label: '오픈부', hasRanking: true, gender: 'male' },
  { code: 'jn_m_gold', org: 'jn', label: '골드부', hasRanking: true, gender: 'male' },
  { code: 'jn_m_general', org: 'jn', label: '일반부', hasRanking: true, gender: 'male' },
  { code: 'jn_m_instructor', org: 'jn', label: '지도자부', hasRanking: true, gender: 'male' },
  { code: 'jn_m_masters', org: 'jn', label: '마스터즈부', hasRanking: false, gender: 'male' },
  { code: 'jn_m_rookie', org: 'jn', label: '신인부', hasRanking: false, gender: 'male' },
  { code: 'jn_m_veteran', org: 'jn', label: '베테랑부', hasRanking: false, gender: 'male' },
  { code: 'jn_m_beginner', org: 'jn', label: '초급자부', hasRanking: false, gender: 'male' },
  { code: 'jn_w_open', org: 'jn', label: '여자오픈부', hasRanking: false, gender: 'female' },
  { code: 'jn_w_winner', org: 'jn', label: '여자우승자부', hasRanking: true, gender: 'female' },
  { code: 'jn_w_rookie', org: 'jn', label: '여자신인부', hasRanking: true, gender: 'female' },
  { code: 'jn_couple', org: 'jn', label: '부부부', hasRanking: false, gender: 'mixed' },
  { code: 'jn_cross', org: 'jn', label: '크로스대회', hasRanking: false, gender: 'mixed' },

  // KTA (대한테니스협회)
  { code: 'kta_m_open', org: 'kta', label: '남자오픈', gender: 'male' },
  { code: 'kta_w_open', org: 'kta', label: '여자오픈', gender: 'female' },
  { code: 'kta_mixed', org: 'kta', label: '혼합복식', gender: 'mixed' },
  { code: 'kta_senior_60', org: 'kta', label: '시니어 60+', gender: 'all' },
  { code: 'kta_senior_65', org: 'kta', label: '시니어 65+', gender: 'all' },

  // KATA (한국동호인테니스협회) — 부수제
  { code: 'kata_1', org: 'kata', label: '1부', gender: 'male' },
  { code: 'kata_2', org: 'kata', label: '2부', gender: 'male' },
  { code: 'kata_3', org: 'kata', label: '3부', gender: 'male' },
  { code: 'kata_4', org: 'kata', label: '4부', gender: 'male' },
  { code: 'kata_5', org: 'kata', label: '5부', gender: 'male' },
  { code: 'kata_w', org: 'kata', label: '여자부', gender: 'female' },

  // KTFS (전국생활체육연합회)
  { code: 'ktfs_open', org: 'ktfs', label: '오픈', gender: 'all' },
  { code: 'ktfs_general', org: 'ktfs', label: '일반', gender: 'all' },
  { code: 'ktfs_beginner', org: 'ktfs', label: '초급', gender: 'all' },
  { code: 'ktfs_w', org: 'ktfs', label: '여자부', gender: 'female' },

  // KSTF (시니어)
  { code: 'kstf_60', org: 'kstf', label: '60+부', gender: 'all' },
  { code: 'kstf_65', org: 'kstf', label: '65+부', gender: 'all' },
  { code: 'kstf_70', org: 'kstf', label: '70+부', gender: 'all' },

  // 지역/클럽 자체
  { code: 'local_open', org: 'local', label: '자체 오픈', gender: 'all' },
  { code: 'local_general', org: 'local', label: '자체 일반', gender: 'all' },
  { code: 'local_rookie', org: 'local', label: '자체 신인', gender: 'all' },
  { code: 'local_w', org: 'local', label: '자체 여자부', gender: 'female' },
];

export const TENNIS_DIVISION_LABELS: Record<string, string> = Object.fromEntries(
  TENNIS_DIVISIONS.map((d) => [d.code, d.label]),
);

export function getDivisionsForOrg(org: string): TennisDivisionDef[] {
  return TENNIS_DIVISIONS.filter((d) => d.org === org);
}

export function getDivisionLabel(code: string): string {
  return TENNIS_DIVISION_LABELS[code] ?? code;
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
  beginner: 0,
  intermediate: 1,
  advanced: 2,
};

export function isValidGrade(sport: Sport, grade: string): grade is Grade {
  if (sport === 'tennis') return (TENNIS_GRADES as readonly string[]).includes(grade);
  return (FUTSAL_GRADES as readonly string[]).includes(grade);
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
  beginner: '초급',
  intermediate: '중급',
  advanced: '고급',
};

export const SPORT_LABELS: Record<Sport, string> = {
  tennis: '테니스',
  futsal: '풋살',
};

export function rankOf(sport: Sport, grade: string): number | null {
  if (sport === 'tennis' && grade in TENNIS_RANK) return TENNIS_RANK[grade as TennisGrade];
  if (sport === 'futsal' && grade in FUTSAL_RANK) return FUTSAL_RANK[grade as FutsalGrade];
  return null;
}
