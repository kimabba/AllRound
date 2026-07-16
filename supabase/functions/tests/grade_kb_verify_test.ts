// grade_kb_verify_test.ts
// 등급체계 KB 정본(docs/kb/grades/*.divisions.json)과 seed 마이그레이션의 일치·무결성 검증.
//
// 아키텍처(P5 KATO 로 확립): JSON 이 기계 판독 정본, seed·HTML 은 뷰.
// 이 테스트가 CI 에서 JSON↔seed 일치를 강제해 복제 드리프트(블로커 #3)를 차단한다.
// 대조는 SQL 파싱 없이 "행 라인 내 문자열 presence" 기반이라 SQL 포맷 변화에 비취약하다.
//
// 경로는 import.meta.url 기준이라 CWD(레포 루트 / supabase/functions 어디서 실행하든) 무관.
// CI: `deno test --config deno.json --allow-env --allow-read tests` (--allow-read 전체 허용).

import { assert, assertEquals } from 'std/assert/mod.ts';

interface Division {
  code: string;
  org_code: string;
  label_ko: string;
  synonyms: string[];
  skill_tier: string | null;
  gender: string;
  age_min: number | null;
  champion_only: boolean;
  event_type: string;
  equiv_group: string | null;
}

interface DivisionKb {
  org_code: string;
  divisions: Division[];
}

async function readText(relFromTestFile: string): Promise<string> {
  return await Deno.readTextFile(new URL(relFromTestFile, import.meta.url));
}

// (JSON 경로, seed 경로, org_code) — 협회를 늘리면 여기 한 줄 추가.
const KBS: Array<{ json: string; seed: string; org: string }> = [
  {
    json: '../../../docs/kb/grades/kato.divisions.json',
    seed: '../../migrations/20260713042834_seed_kato_divisions.sql',
    org: 'kato',
  },
];

for (const kb of KBS) {
  Deno.test(`grade KB [${kb.org}]: JSON 무결성`, async () => {
    const data = JSON.parse(await readText(kb.json)) as DivisionKb;
    assertEquals(data.org_code, kb.org, 'JSON org_code 불일치');
    assert(data.divisions.length > 0, '부서가 비어 있음');

    // code 유일
    const codes = data.divisions.map((d) => d.code);
    assertEquals(new Set(codes).size, codes.length, `code 중복: ${codes}`);

    // org_code 전부 일치
    for (const d of data.divisions) {
      assertEquals(d.org_code, kb.org, `${d.code} 의 org_code 가 ${kb.org} 아님`);
      assert(d.synonyms.length > 0, `${d.code} synonyms 비어 있음`);
    }

    // synonym 이 다른 부서 synonym 의 substring 이면 안 됨(bare 혼합/퓨처스 충돌 방지).
    // mapDivisionsByDict 는 text.includes(synonym) 로 매칭하므로, A 의 synonym 이 B 의
    // on-page 문자열(≈ B 의 synonym)에 포함되면 B 대회에서 A 가 오탐된다.
    for (const a of data.divisions) {
      for (const b of data.divisions) {
        if (a.code === b.code) continue;
        for (const sa of a.synonyms) {
          for (const sb of b.synonyms) {
            assert(
              !sb.includes(sa),
              `${a.code} 의 synonym "${sa}" 가 ${b.code} 의 synonym "${sb}" 의 substring — 충돌`,
            );
          }
        }
      }
    }
  });

  Deno.test(`grade KB [${kb.org}]: JSON ↔ seed 일치`, async () => {
    const data = JSON.parse(await readText(kb.json)) as DivisionKb;
    const seed = await readText(kb.seed);
    const seedLines = seed.split('\n');

    // seed 의 INSERT value 행 수 == JSON 부서 수 (양방향).
    const seedCodeMatches = seed.match(/\(\s*'kato_[a-z0-9_]+'/g) ?? [];
    assertEquals(
      seedCodeMatches.length,
      data.divisions.length,
      `seed INSERT 행 수(${seedCodeMatches.length}) != JSON 부서 수(${data.divisions.length})`,
    );

    for (const d of data.divisions) {
      // 해당 code 를 가진 seed 행을 정확히 하나 찾는다.
      const rows = seedLines.filter((l) => l.includes(`'${d.code}'`));
      assertEquals(rows.length, 1, `seed 에서 ${d.code} 행이 정확히 1개가 아님(${rows.length})`);
      const row = rows[0];

      // 매칭 핵심 필드: synonyms 전부 · gender · event_type 이 행에 존재.
      for (const syn of d.synonyms) {
        assert(row.includes(syn), `seed ${d.code} 행에 synonym "${syn}" 없음`);
      }
      assert(row.includes(`'${d.gender}'`), `seed ${d.code} 행에 gender '${d.gender}' 없음`);
      assert(
        row.includes(`'${d.event_type}'`),
        `seed ${d.code} 행에 event_type '${d.event_type}' 없음`,
      );
      // skill_tier: 값이 있으면 따옴표 값 존재, null 이면 bare null 존재.
      if (d.skill_tier !== null) {
        assert(
          row.includes(`'${d.skill_tier}'`),
          `seed ${d.code} 행에 skill_tier '${d.skill_tier}' 없음`,
        );
      } else {
        assert(row.includes('null'), `seed ${d.code} 행에 null(skill_tier) 없음`);
      }
      // champion_only: true/false 존재.
      assert(
        row.includes(String(d.champion_only)),
        `seed ${d.code} 행에 champion_only ${d.champion_only} 없음`,
      );
    }
  });
}
