enum Sport { tennis, futsal }

const tennisGrades = ['under1y', 'y1to3', 'y3to5', 'over5y'];
const futsalGrades = ['beginner', 'intermediate', 'advanced'];

const gradeLabels = <String, String>{
  'under1y':      '1년 미만',
  'y1to3':        '1~3년',
  'y3to5':        '3~5년',
  'over5y':       '5년 이상',
  'beginner':     '초급',
  'intermediate': '중급',
  'advanced':     '고급',
};

const sportLabels = <Sport, String>{
  Sport.tennis: '테니스',
  Sport.futsal: '풋살',
};

Sport sportFromString(String s) =>
    s == 'futsal' ? Sport.futsal : Sport.tennis;

String sportToString(Sport s) => s == Sport.futsal ? 'futsal' : 'tennis';

List<String> gradesFor(Sport sport) =>
    sport == Sport.tennis ? tennisGrades : futsalGrades;

String gradeLabel(String grade) => gradeLabels[grade] ?? grade;
String sportLabel(Sport sport) => sportLabels[sport] ?? '';
String sportLabelFromString(String s) => sportLabel(sportFromString(s));

// =========================
// Tennis Org (협회) — Edge Functions enums.ts 와 1:1 동기화
// =========================
const tennisOrgs = <String>[
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
];

const tennisOrgLabels = <String, String>{
  'kta': '대한테니스협회 (KTA)',
  'kato': '한국테니스발전협의회 (KATO)',
  'kata': '한국동호인테니스협회 (KATA)',
  'ktfs': '국민생활체육 전국테니스연합회 (KTFS)',
  'kstf': '한국시니어테니스연맹 (KSTF, 60+)',
  'kssta': '한국슈퍼시니어테니스협회 (KSSTA)',
  'kasta': '단식 테니스 (KASTA / 단테매)',
  'gj': '광주광역시테니스협회 (GJTA)',
  'jn': '전라남도테니스협회 (JNTA)',
  'local': '시·군 또는 클럽 자체',
};

const tennisOrgShortLabels = <String, String>{
  'kta': 'KTA',
  'kato': 'KATO',
  'kata': 'KATA',
  'ktfs': 'KTFS',
  'kstf': 'KSTF',
  'kssta': 'KSSTA',
  'kasta': 'KASTA',
  'gj': '광주협회',
  'jn': '전남협회',
  'local': '시·군/클럽',
};

bool isValidTennisOrg(String value) => tennisOrgs.contains(value);
String tennisOrgLabel(String org) => tennisOrgLabels[org] ?? org;
String tennisOrgShortLabel(String org) => tennisOrgShortLabels[org] ?? org;

// =========================
// Region (권역)
// =========================
const regionCodes = <String>[
  'gwangju',
  'jeonnam',
  'seoul_metro',
  'busan_ulsan_gn',
  'daegu_gb',
  'chungcheong',
  'gangwon',
  'jeju',
];

const regionLabels = <String, String>{
  'gwangju': '광주',
  'jeonnam': '전남',
  'seoul_metro': '수도권',
  'busan_ulsan_gn': '부산·울산·경남',
  'daegu_gb': '대구·경북',
  'chungcheong': '충청',
  'gangwon': '강원',
  'jeju': '제주',
};

bool isValidRegionCode(String value) => regionCodes.contains(value);
String regionLabel(String code) => regionLabels[code] ?? code;
