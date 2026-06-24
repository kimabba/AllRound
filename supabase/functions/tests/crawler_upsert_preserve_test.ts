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
  manual_description: false,
};

interface CapturedUpdate {
  payload: Row;
}

/**
 * upsertTournament 가 호출하는 체인만 구현한 최소 fake.
 *   - from('tournaments').select(...).eq().eq().maybeSingle() → 기존 행
 *   - from('tournaments').update(payload).eq() → payload 캡처
 * 그 외 호출은 테스트 시나리오(rawHtml 미전달)에서 발생하지 않는다.
 */
function makeFakeClient(captured: CapturedUpdate[]): AuditHandle['supabase'] {
  const updateBuilder = (payload: Row) => ({
    eq: (_col: string, _val: unknown) => {
      captured.push({ payload });
      return Promise.resolve({ data: null, error: null });
    },
  });
  const selectBuilder = () => ({
    eq: (_c: string, _v: unknown) => ({
      eq: (_c2: string, _v2: unknown) => ({
        maybeSingle: () => Promise.resolve({ data: EXISTING_ROW, error: null }),
      }),
    }),
  });
  const fake = {
    from: (_table: string) => ({
      select: (_cols: string) => selectBuilder(),
      update: (payload: Row) => updateBuilder(payload),
    }),
  };
  // upsertTournament 는 SupabaseClient 의 from() 만 사용한다. 최소 fake 를
  // 해당 인터페이스로 좁혀 전달(unknown 경계 후 단언).
  return fake as unknown as AuditHandle['supabase'];
}

function makeAudit(captured: CapturedUpdate[]): AuditHandle {
  return {
    id: 'audit-1',
    source: 'jntennis',
    supabase: makeFakeClient(captured),
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
