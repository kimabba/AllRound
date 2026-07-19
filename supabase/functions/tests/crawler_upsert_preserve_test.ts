// crawler_upsert_preserve_test.ts
// upsertTournament 의 UPDATE 분기 regulation_* 보존 동작 (P2⑥) 단위 테스트.
//
// 데이터 무결성: 일시적 파싱 미스로 regulation_fields/notes/body 가 undefined 로
// 들어오면 기존 구조화 데이터를 null 로 지우지 않고 보존해야 한다. 추출값이
// 정의돼 있을 때(빈 배열 포함)만 갱신한다.
//
// upsertTournament 는 Supabase 클라이언트의 쿼리 빌더 체인에 의존하므로,
// UPDATE payload 를 가로채는 최소 fake 클라이언트로 검증한다. (rawHtml 미전달 →
// saveRawDocument 경로를 타지 않아 read/update 체인만 모킹하면 충분)

import { assert, assertEquals } from 'std/assert/mod.ts';
import { type AuditHandle, type CrawlerTournament, upsertTournament } from '../_shared/crawler.ts';

type Row = Record<string, unknown>;

// 기존 tournaments 행(파싱 성공 이력으로 구조화 데이터 보유) 모킹.
const EXISTING_ROW: Row = {
  id: 'tour-1',
  title: '기존 대회',
  start_date: '2026-07-04',
  application_deadline: null,
  eligible_grades: [],
  region: '전남',
  location: null,
  manual_description: false,
  format_source_hash: null,
};

interface CapturedUpdate {
  payload: Row;
}

/**
 * upsertTournament 가 호출하는 체인만 구현한 최소 fake.
 *   - from('tournaments').select(...).eq().eq().maybeSingle() → 기존 행
 *   - from('tournaments').update(payload).eq() → payload 캡처
 *   - from('crawl_documents').upsert(...) → rawHtml 전달 시 saveRawDocument 가 타는 경로
 *     (existing.id 가 있으므로 tournament_id 조회 select 는 발생하지 않는다)
 * existingRow 를 인자로 받아 format_source_hash 등을 케이스별로 바꿀 수 있다.
 */
function makeFakeClient(
  captured: CapturedUpdate[],
  existingRow: Row = EXISTING_ROW,
): AuditHandle['supabase'] {
  const updateBuilder = (payload: Row) => ({
    eq: (_col: string, _val: unknown) => {
      captured.push({ payload });
      return Promise.resolve({ data: null, error: null });
    },
  });
  const selectBuilder = () => ({
    eq: (_c: string, _v: unknown) => ({
      eq: (_c2: string, _v2: unknown) => ({
        maybeSingle: () => Promise.resolve({ data: existingRow, error: null }),
      }),
    }),
  });
  const fake = {
    from: (table: string) => {
      if (table === 'crawl_documents') {
        return {
          upsert: (_payload: Row, _opts?: unknown) => Promise.resolve({ data: null, error: null }),
        };
      }
      return {
        select: (_cols: string) => selectBuilder(),
        update: (payload: Row) => updateBuilder(payload),
      };
    },
  };
  // upsertTournament 는 SupabaseClient 의 from() 만 사용한다. 최소 fake 를
  // 해당 인터페이스로 좁혀 전달(unknown 경계 후 단언).
  return fake as unknown as AuditHandle['supabase'];
}

function makeAudit(captured: CapturedUpdate[], existingRow: Row = EXISTING_ROW): AuditHandle {
  return {
    id: 'audit-1',
    source: 'jntennis',
    supabase: makeFakeClient(captured, existingRow),
    fetched: 0,
    inserted: 0,
    updated: 0,
  };
}

const BASE_TOURNAMENT: CrawlerTournament = {
  title: '갱신 대회',
  start_date: '2026-07-04',
  eligible_grades: ['jn_m_general'],
  source_url: 'https://www.jntennis.kr/sub5_2_2_view.php?sid=109',
};

Deno.test('UPDATE preserves regulation_* when extraction is undefined (parser miss)', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  // regulation_* 미지정(undefined) — 일시적 파싱 미스 모사.
  const result = await upsertTournament(audit, 'tennis', { ...BASE_TOURNAMENT });
  assertEquals(result, 'updated');
  assertEquals(captured.length, 1);
  const p = captured[0].payload;
  // 컬럼 자체가 payload 에 없어야 함 → 기존값 보존(덮어쓰지 않음)
  assert(!('regulation_fields' in p), 'regulation_fields must be omitted when undefined');
  assert(!('regulation_notes' in p), 'regulation_notes must be omitted when undefined');
  assert(!('regulation_body' in p), 'regulation_body must be omitted when undefined');
});

Deno.test('UPDATE sets regulation_* when extraction succeeds', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  const result = await upsertTournament(audit, 'tennis', {
    ...BASE_TOURNAMENT,
    regulation_fields: [{ label: '주최', value: '영암군 체육회' }],
    regulation_notes: ['보험 가입함'],
    regulation_body: '일시: 2026년 7월 4일',
  });
  assertEquals(result, 'updated');
  const p = captured[0].payload;
  assertEquals(p.regulation_fields, [{ label: '주최', value: '영암군 체육회' }]);
  assertEquals(p.regulation_notes, ['보험 가입함']);
  assertEquals(p.regulation_body, '일시: 2026년 7월 4일');
});

Deno.test('UPDATE preserves eligible_grades when division unmapped (codes=[])', async () => {
  // 부서 미매칭(사전 synonym 하나도 안 맞음) → eligible_grades=[] 로 들어옴.
  // 이미 published 된 대회의 기존 등급을 조용히 비우지 않도록 보존해야 한다.
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  const result = await upsertTournament(audit, 'tennis', {
    ...BASE_TOURNAMENT,
    eligible_grades: [],
    division_label_local: undefined,
  });
  assertEquals(result, 'updated');
  const p = captured[0].payload;
  assert(!('eligible_grades' in p), 'eligible_grades must be omitted when unmapped ([])');
  assert(!('division_label_local' in p), 'division_label_local must be omitted when unmapped');
});

Deno.test('UPDATE clears eligible_grades when source explicitly says division pending', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  const result = await upsertTournament(audit, 'tennis', {
    ...BASE_TOURNAMENT,
    eligible_grades: [],
    division_label_local: '부서추후공지',
    clear_eligible_grades: true,
  });
  assertEquals(result, 'updated');
  const p = captured[0].payload;
  assertEquals(p.eligible_grades, []);
  assertEquals(p.division_label_local, '부서추후공지');
});

Deno.test('UPDATE sets eligible_grades when division mapped (codes non-empty)', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  await upsertTournament(audit, 'tennis', {
    ...BASE_TOURNAMENT,
    eligible_grades: ['jn_m_general'],
    division_label_local: '남자일반부',
  });
  const p = captured[0].payload;
  assertEquals(p.eligible_grades, ['jn_m_general']);
  assertEquals(p.division_label_local, '남자일반부');
});

Deno.test('UPDATE clears regulation_* with defined empty array / empty string', async () => {
  // 의도적 클리어 케이스: 추출이 "정의된 빈 결과"면 set 해 갱신.
  // (파서는 빈 결과를 undefined 로 주지만, 정의된 빈 값이 오면 그대로 반영)
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured);
  await upsertTournament(audit, 'tennis', {
    ...BASE_TOURNAMENT,
    regulation_fields: [],
    regulation_notes: [],
    regulation_body: '',
  });
  const p = captured[0].payload;
  assert('regulation_fields' in p, 'defined empty array should be set');
  assertEquals(p.regulation_fields, []);
  assertEquals(p.regulation_notes, []);
  assertEquals(p.regulation_body, '');
});

Deno.test('upsert: 파서가 prize/format 미방출(undefined)이면 기존 값 보존', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured, { ...EXISTING_ROW, format_source_hash: 'oldhash' });
  const t: CrawlerTournament = {
    title: '기존 대회',
    start_date: '2026-07-04',
    eligible_grades: [],
    source_url: 'https://x/1',
    // description/prize/format/regulation_* 미설정(undefined) — 파서가 요강 방출 안 함
  };
  await upsertTournament(audit, 'tennis', t); // rawHtml 미전달
  const p = captured[0].payload;
  assert(!('prize' in p), 'prize를 payload에 넣지 않아야 함');
  assert(!('format' in p), 'format를 payload에 넣지 않아야 함');
  assert(!('description' in p), 'description 미방출 시 payload 제외');
});

Deno.test('upsert: 재크롤로 content_hash 바뀌면 format_status=pending 재설정', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured, { ...EXISTING_ROW, format_source_hash: 'oldhash' });
  const t: CrawlerTournament = {
    title: '기존 대회',
    start_date: '2026-07-04',
    eligible_grades: [],
    source_url: 'https://x/1',
  };
  await upsertTournament(audit, 'tennis', t, '<html>바뀐 원문</html>');
  const p = captured[0].payload;
  assertEquals(p.format_status, 'pending');
  assertEquals(p.format_claim_token, null);
  assertEquals(p.claimed_at, null);
});

Deno.test('upsert: 원문이 같아도 파서 장소 결과가 바뀌면 재정형화 대기', async () => {
  const captured: CapturedUpdate[] = [];
  const audit = makeAudit(captured, {
    ...EXISTING_ROW,
    location: null,
    format_source_hash: null,
  });
  await upsertTournament(
    audit,
    'tennis',
    {
      ...BASE_TOURNAMENT,
      location: '공주시립테니스코트 외 3곳',
    },
    '<html>동일한 원문</html>',
  );

  const p = captured[0].payload;
  assertEquals(p.location, '공주시립테니스코트 외 3곳');
  assertEquals(p.format_status, 'pending');
  assertEquals(p.format_claim_token, null);
  assertEquals(p.claimed_at, null);
});
