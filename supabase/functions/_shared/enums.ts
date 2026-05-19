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

const TENNIS_RANK: Record<TennisGrade, number> = {
  under1y: 0,
  y1to3:   1,
  y3to5:   2,
  over5y:  3,
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
  under1y:      '1년 미만',
  y1to3:        '1~3년',
  y3to5:        '3~5년',
  over5y:       '5년 이상',
  beginner:     '초급',
  intermediate: '중급',
  advanced:     '고급',
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
