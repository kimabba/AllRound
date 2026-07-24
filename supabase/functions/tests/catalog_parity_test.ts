// catalog_parity_test.ts (JY-146 Step 0)
// 종목·등급 카탈로그가 Dart / Deno TS / Postgres 3계층에 복제돼 있어, 한 곳만 고치면
// 조용히 갈라진다. 이 테스트가 3벌 동기화를 CI 에서 강제해 드리프트를 차단한다.
//
// 정본은 각각: 등급코드=DB CHECK(user_sports_grade_check), 종목값=DB `sport` enum,
// 라벨=코드(DB 미보유). 여기서는 "강제"가 아니라 "3벌 일치"만 검증한다.
//
// CI 는 Deno net 불가(--allow-env --allow-read)라 DB 실조회 대신 마이그레이션 SQL 을 읽는다.
// eligible_grades 실값 검증(부서코드가 tennis_divisions 에 실재하는지)은 로컬 E2E 몫이다.
//
// 경로는 import.meta.url 기준이라 CWD 무관.
// CI: `deno test --config deno.json --allow-env --allow-read tests`

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  FUTSAL_GRADES,
  GRADE_LABELS,
  isValidGrade,
  SPORT_LABELS,
  TENNIS_GRADES,
} from '../_shared/enums.ts';

const DART_GRADES = '../../../app/lib/utils/grade_labels.dart';
const MIGRATIONS = new URL('../../migrations/', import.meta.url);

async function readText(relFromTestFile: string): Promise<string> {
  return await Deno.readTextFile(new URL(relFromTestFile, import.meta.url));
}

/** 파서가 0건을 뽑으면 침묵 통과가 되므로 즉시 실패시킨다. */
function requireNonEmpty<T>(items: T[], what: string): T[] {
  assert(items.length > 0, `파서가 ${what} 를 한 건도 추출하지 못했다 — 정규식과 원본 확인 필요`);
  return items;
}

/** `const <name> = ['a', 'b'];` 형태의 Dart 리스트 리터럴. */
function dartStringList(src: string, name: string): string[] {
  const block = src.match(new RegExp(`const ${name}\\s*=\\s*\\[([^\\]]*)\\]`));
  assert(block, `Dart 에서 ${name} 선언을 찾지 못했다`);
  return requireNonEmpty([...block[1].matchAll(/'([^']*)'/g)].map((m) => m[1]), `Dart ${name}`);
}

/** `const <name> = <String, String>{ 'k': 'v', };` 형태의 Dart 맵 리터럴. */
function dartStringMap(src: string, name: string): Record<string, string> {
  const block = src.match(new RegExp(`const ${name}\\s*=\\s*<String, String>\\{([\\s\\S]*?)\\};`));
  assert(block, `Dart 에서 ${name} 선언을 찾지 못했다`);
  const entries = requireNonEmpty(
    [...block[1].matchAll(/'([^']*)'\s*:\s*'([^']*)'/g)].map((m) => [m[1], m[2]] as const),
    `Dart ${name}`,
  );
  return Object.fromEntries(entries);
}

/**
 * 해당 토큰을 담은 마이그레이션 중 파일명 정렬상 마지막 것 = 현행 정본.
 * (숫자 프리픽스 071 < 타임스탬프 2026… 라 신규 마이그가 항상 뒤에 온다.)
 */
async function latestMigrationWith(token: string): Promise<{ name: string; sql: string }> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(MIGRATIONS)) {
    if (entry.isFile && entry.name.endsWith('.sql')) names.push(entry.name);
  }
  requireNonEmpty(names, '마이그레이션 파일');
  for (const name of names.sort().reverse()) {
    const sql = await Deno.readTextFile(new URL(name, MIGRATIONS));
    if (sql.includes(token)) return { name, sql };
  }
  throw new Error(`마이그레이션에서 "${token}" 을 찾지 못했다`);
}

/** CHECK 안의 `sport = 'tennis' AND grade IN ('a', 'b')` — 같은 파일에 여러 벌이면 마지막(=교체 후). */
function checkGradesFor(sql: string, sport: string): string[] {
  const re = new RegExp(`sport\\s*=\\s*'${sport}'\\s+and\\s+grade\\s+in\\s*\\(([^)]*)\\)`, 'gi');
  const matches = requireNonEmpty([...sql.matchAll(re)], `CHECK 의 ${sport} 등급 목록`);
  const last = matches[matches.length - 1];
  return requireNonEmpty(
    [...last[1].matchAll(/'([^']*)'/g)].map((m) => m[1]),
    `CHECK 의 ${sport} 등급값`,
  );
}

const sorted = (values: Iterable<string>) => [...values].sort();

Deno.test('등급코드 3벌 일치 — Dart / TS / DB CHECK', async () => {
  const dart = await readText(DART_GRADES);
  const { name, sql } = await latestMigrationWith('user_sports_grade_check');

  for (
    const [sport, ts, dartName] of [
      ['tennis', TENNIS_GRADES, 'tennisGrades'],
      ['futsal', FUTSAL_GRADES, 'futsalGrades'],
    ] as const
  ) {
    const db = sorted(checkGradesFor(sql, sport));
    assertEquals(sorted(dartStringList(dart, dartName)), db, `${sport}: Dart ↔ DB(${name}) 불일치`);
    assertEquals(sorted(ts), db, `${sport}: TS ↔ DB(${name}) 불일치`);
  }
});

Deno.test('등급 라벨 일치 — Dart ↔ TS, 키집합 = 등급코드 전체', async () => {
  const dartLabels = dartStringMap(await readText(DART_GRADES), 'gradeLabels');

  assertEquals(dartLabels, GRADE_LABELS, 'gradeLabels(Dart) ↔ GRADE_LABELS(TS) 불일치');
  assertEquals(
    sorted(Object.keys(GRADE_LABELS)),
    sorted([...TENNIS_GRADES, ...FUTSAL_GRADES]),
    '라벨 키집합이 등급코드와 다르다 — 라벨 누락 또는 폐기 등급 잔존',
  );
});

Deno.test('종목값 스냅샷 — Dart enum / TS 타입 / DB sport enum', async () => {
  const SPORTS = ['futsal', 'tennis'];
  const dart = await readText(DART_GRADES);
  const { sql } = await latestMigrationWith('create type sport');

  const dartEnum = dart.match(/enum Sport\s*\{([^}]*)\}/);
  assert(dartEnum, 'Dart 에서 enum Sport 선언을 찾지 못했다');
  assertEquals(
    sorted(
      requireNonEmpty(dartEnum[1].split(',').map((v) => v.trim()).filter(Boolean), 'Dart 종목'),
    ),
    SPORTS,
    'Dart enum Sport 가 스냅샷과 다르다 — 종목 추가는 JY-146 P4 범위',
  );

  const dbEnum = sql.match(/create type sport as enum\s*\(([^)]*)\)/i);
  assert(dbEnum, '마이그레이션에서 sport enum 정의를 찾지 못했다');
  assertEquals(
    sorted(requireNonEmpty([...dbEnum[1].matchAll(/'([^']*)'/g)].map((m) => m[1]), 'DB 종목')),
    SPORTS,
    'DB sport enum 이 스냅샷과 다르다',
  );

  // enum 값 추가는 ALTER TYPE 으로도 가능하다 — 그 경로로 새면 위 스냅샷이 침묵한다.
  for await (const entry of Deno.readDir(MIGRATIONS)) {
    if (!entry.isFile || !entry.name.endsWith('.sql')) continue;
    const migration = await Deno.readTextFile(new URL(entry.name, MIGRATIONS));
    assert(
      !/alter type\s+(public\.)?sport\s+add value/i.test(migration),
      `${entry.name}: sport enum 에 값이 추가됐다 — 종목 확장은 JY-146 P4 범위`,
    );
  }

  assertEquals(sorted(Object.keys(SPORT_LABELS)), SPORTS, 'SPORT_LABELS 키가 종목값과 다르다');
});

Deno.test('eligible_grades 도메인 계약 — 종목 간 등급 교차 오염 차단', () => {
  // 풋살 경로(마이그 075:148 `us.grade = ANY(t.eligible_grades)`)는 등급코드끼리 비교한다.
  for (const grade of FUTSAL_GRADES) {
    assert(isValidGrade('futsal', grade), `futsal 등급 ${grade} 이 거부됐다`);
  }
  for (const alien of [...TENNIS_GRADES, 'gj_m_gold', 'kata_1']) {
    assert(!isValidGrade('futsal', alien), `futsal 도메인이 ${alien} 을 통과시켰다`);
  }

  // 테니스 경로(075:140 `expand_gj_jn_codes(...) && t.eligible_grades`)는 부서코드를 쓴다.
  for (const code of ['gj_m_gold', 'jn_w_open', 'kata_1', 'kta_m_open']) {
    assert(isValidGrade('tennis', code), `부서코드 ${code} 가 거부됐다`);
  }
  for (const alien of [...FUTSAL_GRADES, 'nope_x', '_leading', 'nounderscore']) {
    assert(!isValidGrade('tennis', alien), `tennis 도메인이 ${alien} 을 통과시켰다`);
  }
});
