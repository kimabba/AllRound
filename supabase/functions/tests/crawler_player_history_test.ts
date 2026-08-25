import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';
import {
  crawlPlayerHistories,
  dedupeHistoryRows,
  fetchAllRows,
  looksLikeHistoryPage,
  normalizeResultRound,
  parsePlayerHistoryRows,
  playerHistoryUrl,
  selectHistoryCandidates,
  type SupabaseLike,
} from '../_shared/crawler/parsers/gnuboard_player_history.ts';

const html = await Deno.readTextFile(
  new URL('./fixtures/gj_player_history.html', import.meta.url),
);

Deno.test('픽스처 첫 행 필드를 전부 대조한다 (컬럼이 뒤바뀌면 실패해야 한다)', () => {
  const rows = parsePlayerHistoryRows(html);
  assertEquals(rows.length, 15);
  const first = rows[0];
  assertEquals(first.tournamentName, '2026 가상새봄배 전국대회 및 광주생활체육 테니스대회');
  assertEquals(first.eventRaw, '지동부');
  assertEquals(first.resultRaw, '8');
  assertEquals(first.resultRound, 8);
  assertEquals(first.points, 91);
  assertEquals(first.playedOn, '2026-07-05');
});

Deno.test('픽스처에 순위 표기 혼재가 실제로 존재한다 (맨숫자·N강 둘 다)', () => {
  const rows = parsePlayerHistoryRows(html);
  const plainDigit = rows.filter((r) => /^\d+$/.test(r.resultRaw));
  const nGang = rows.filter((r) => /^\d+강$/.test(r.resultRaw));
  // 이 파서의 존재 이유 — 협회가 같은 페이지에서 두 표기를 섞어 준다.
  assertEquals(plainDigit.length >= 1, true);
  assertEquals(nGang.length >= 1, true);
  // 같은 라운드값(16강)이 두 표기 방식 모두에서 나오는지도 확인한다.
  assertEquals(plainDigit.some((r) => r.resultRound === 16), true);
  assertEquals(nGang.some((r) => r.resultRound === 16), true);
});

Deno.test('맨숫자 표기를 진출 라운드로 정규화한다', () => {
  assertEquals(normalizeResultRound('1'), 1);
  assertEquals(normalizeResultRound('2'), 2);
  assertEquals(normalizeResultRound('4'), 4);
  assertEquals(normalizeResultRound('16'), 16);
});

Deno.test('N강 표기를 같은 값으로 정규화한다', () => {
  assertEquals(normalizeResultRound('16강'), 16);
  assertEquals(normalizeResultRound('4강'), 4);
  assertEquals(normalizeResultRound('32강'), 32);
});

Deno.test('우승·준우승 표기를 정규화한다', () => {
  assertEquals(normalizeResultRound('우승'), 1);
  assertEquals(normalizeResultRound('준우승'), 2);
});

Deno.test('못 읽는 표기는 NULL 이다 — 추측값으로 채우지 않는다', () => {
  assertEquals(normalizeResultRound('예선탈락'), null);
  assertEquals(normalizeResultRound(''), null);
  assertEquals(normalizeResultRound('-'), null);
});

Deno.test('정규화에 실패해도 원문은 남는다', () => {
  const oddRow = `
    <table><tr>
      <td>zz대회</td><td>예선탈락</td><td>골드부</td><td>5</td><td>2026-05-01</td>
    </tr></table>`;
  const rows = parsePlayerHistoryRows(oddRow);
  assertEquals(rows[0].resultRound, null);
  assertEquals(rows[0].resultRaw, '예선탈락');
});

Deno.test('협회 날짜 표기를 ISO 로 바꾼다 (실측: 2026년 7월 05일)', () => {
  const row = `
    <table><tr>
      <td>zz대회</td><td>1</td><td>골드부</td><td>10</td><td>2026년 7월 05일</td>
    </tr></table>`;
  assertEquals(parsePlayerHistoryRows(row)[0].playedOn, '2026-07-05');
});

Deno.test('날짜를 못 읽는 행은 버린다 — 유니크 키를 만들 수 없다', () => {
  const row = `
    <table><tr>
      <td>zz대회</td><td>1</td><td>골드부</td><td>10</td><td>미정</td>
    </tr></table>`;
  assertEquals(parsePlayerHistoryRows(row).length, 0);
});

Deno.test('천 단위 콤마를 제거한다', () => {
  const row = `
    <table><tr>
      <td>zz대회</td><td>1</td><td>골드부</td><td>1,000</td><td>2026-05-01</td>
    </tr></table>`;
  assertEquals(parsePlayerHistoryRows(row)[0].points, 1000);
});

Deno.test('개인 이력 URL 을 만든다 (페이지 포함)', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr', 'vudghk2116', 1),
    'https://gjtennis.kr/sub4_6_rank.php?userid=vudghk2116&page=1',
  );
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr', 'vudghk2116', 3),
    'https://gjtennis.kr/sub4_6_rank.php?userid=vudghk2116&page=3',
  );
});

Deno.test('base 의 후행 슬래시를 정리한다', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr/', 'abc', 1),
    'https://gjtennis.kr/sub4_6_rank.php?userid=abc&page=1',
  );
});

Deno.test('아이디를 URL 인코딩한다', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr', 'a b&c', 1),
    'https://gjtennis.kr/sub4_6_rank.php?userid=a%20b%26c&page=1',
  );
});

// ── crawlPlayerHistories — 조용한 성공을 만드는 세 함정 (codex 적대 리뷰 채택분) ──────

function withFetch(handler: (url: string) => Response, fn: () => Promise<void>): Promise<void> {
  const original = globalThis.fetch;
  globalThis.fetch =
    ((url: string | URL) => Promise.resolve(handler(url.toString()))) as typeof fetch;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

const ONE_ROW_HTML = `
  <table><tr>
    <td>zz대회</td><td>1</td><td>골드부</td><td>10</td><td>2026-05-01</td>
  </tr></table>`;
// 헤더/안내 행만 있는 표 — 5셀 미만이라 파싱 결과가 0행이다. 표 헤더(<th>)가 없어
// looksLikeHistoryPage 는 거짓이다 — 차단·에러 페이지를 흉내낸다.
const ZERO_ROW_HTML = `<table><tr><td>등록된 전적이 없습니다</td></tr></table>`;
// 실제 협회 헤더 그대로, 데이터 행은 없다 — "아직 이력 없는 선수"를 흉내낸다.
const HEADER_ONLY_HTML = `
  <table><tr>
    <th width="">대회명</th><th width="">순위</th><th width="">종목</th>
    <th width="">포인트</th><th width="">대회일</th>
  </tr></table>`;
const NO_HEADER_HTML = `<html><body>로그인이 필요합니다</body></html>`;

function makeDb(opts: {
  links?: { org_player_id: string }[];
  rankings?: { org_player_id: string | null; total_points: number }[];
  state?: { org_player_id: string; last_points: number; last_crawled_at: string }[];
  fromThrows?: boolean;
  rpcThrows?: boolean;
}): { db: SupabaseLike; rpcCalls: { fn: string; args: unknown }[] } {
  const rpcCalls: { fn: string; args: unknown }[] = [];
  const db = {
    from(table: string) {
      if (opts.fromThrows) throw new Error('boom: from');
      if (table === 'org_player_links') {
        return {
          select() {
            return {
              eq() {
                return {
                  eq() {
                    return Promise.resolve({ data: opts.links ?? [], error: null });
                  },
                };
              },
            };
          },
        };
      }
      if (table === 'org_rankings') {
        return {
          select() {
            return {
              eq() {
                return {
                  range() {
                    return Promise.resolve({ data: opts.rankings ?? [], error: null });
                  },
                };
              },
            };
          },
        };
      }
      // org_player_history_crawl_state
      return {
        select() {
          return {
            eq() {
              return {
                range() {
                  return Promise.resolve({ data: opts.state ?? [], error: null });
                },
              };
            },
          };
        },
      };
    },
    rpc(fn: string, args: Record<string, unknown>) {
      if (opts.rpcThrows) throw new Error('boom: rpc');
      rpcCalls.push({ fn, args });
      return Promise.resolve({ error: null });
    },
  } as unknown as SupabaseLike;
  return { db, rpcCalls };
}

// ── looksLikeHistoryPage — "아직 이력 없음"과 "차단/레이아웃 변경"을 가르는 신호 ──────

Deno.test('looksLikeHistoryPage: 실제 픽스처는 참이다', () => {
  assertEquals(looksLikeHistoryPage(html), true);
});

Deno.test('looksLikeHistoryPage: 헤더만 있고 데이터 행이 없어도 참이다 (이력 없음과 차단을 가르는 신호)', () => {
  assertEquals(looksLikeHistoryPage(HEADER_ONLY_HTML), true);
});

Deno.test('looksLikeHistoryPage: 헤더가 없는 페이지는 거짓이다', () => {
  assertEquals(looksLikeHistoryPage(NO_HEADER_HTML), false);
});

Deno.test('1페이지가 0행 + 표 헤더 없으면 failures 에 기록한다 (레이아웃 변경·차단 페이지가 조용히 성공하지 않게)', async () => {
  await withFetch(() => new Response(ZERO_ROW_HTML, { status: 200 }), async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, ['이력 p1 p1: 0행, 표 헤더 없음 — 레이아웃 변경 의심']);
    assertEquals(rpcCalls.length, 0); // 0행이라 upsert 도 호출되지 않는다
  });
});

Deno.test('1페이지가 0행이어도 표 헤더가 있으면 failures 에 남지 않는다 (아직 이력 없는 선수)', async () => {
  await withFetch(() => new Response(HEADER_ONLY_HTML, { status: 200 }), async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(rpcCalls.length, 0);
  });
});

Deno.test('둘째 페이지부터의 0행 + 표 헤더 있음은 정상 종료다 — failures 에 남지 않는다', async () => {
  let call = 0;
  await withFetch(() => {
    call++;
    return new Response(call === 1 ? ONE_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(rpcCalls.length, 1);
  });
});

// 2라운드 codex 리뷰가 잡은 결함: looksLikeHistoryPage 판정을 1페이지에만 걸면
// 2페이지 이후 에러/차단/로그인 페이지가 그대로 "범위 밖"으로 삼켜져, 1페이지
// 데이터만 적재되고 나머지가 실패 기록 없이 사라진다. 페이지 번호로 분기하지
// 않고 0행이 나온 모든 페이지에 같은 판정을 걸어야 이게 안 생긴다.
Deno.test('1페이지 정상 + 2페이지가 표 헤더 없는 0행이면 failures 에 기록하고 적재하지 않는다', async () => {
  let call = 0;
  await withFetch(() => {
    call++;
    // 1페이지는 정상, 2페이지부터 차단/에러 페이지(표 헤더 없음)를 흉내낸다.
    return new Response(call === 1 ? ONE_ROW_HTML : NO_HEADER_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures.length, 1);
    assertStringIncludes(failures[0], 'p2');
    assertStringIncludes(failures[0], '표 헤더 없음');
    // 1페이지 15행이 있어도 upsert 하지 않는다 — 몇 페이지까지 받았는지 모르는 채
    // 부분 적재하는 것보다 다음 크롤에서 온전히 받는 편이 낫다(다른 pageFailed 경로와 동일).
    assertEquals(rpcCalls.length, 0);
  });
});

Deno.test('1페이지 정상 + 2페이지가 표 헤더만 있는 0행이면 실패 없이 정상 종료한다', async () => {
  let call = 0;
  await withFetch(() => {
    call++;
    return new Response(call === 1 ? ONE_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(rpcCalls.length, 1); // 1페이지 1행이 정상 적재된다
  });
});

Deno.test('MAX_HISTORY_PAGES(20) 전부 꽉 채우면 잘렸다는 신호를 failures 에 남긴다', async () => {
  await withFetch(() => new Response(ONE_ROW_HTML, { status: 200 }), async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures.length, 1);
    assertStringIncludes(failures[0], '20페이지 상한 도달');
    // 데이터는 있는 만큼(20페이지 분) 그대로 적재한다 — 잘렸다는 신호와 적재는 별개다.
    assertEquals(rpcCalls.length, 1);
  });
});

Deno.test('org_player_links 조회가 예외를 던져도 크롤 전체가 죽지 않는다', async () => {
  const { db } = makeDb({ fromThrows: true });
  const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
  assertEquals(failures.length, 1);
  assertStringIncludes(failures[0], '연결 목록 조회 예외');
});

Deno.test('upsert RPC 가 예외를 던져도 크롤 전체가 죽지 않는다', async () => {
  // 실제로 upsert 를 타려면 rows 가 있어야 하므로 첫 페이지만 값을 주고 끝낸다.
  await withFetch((url) => {
    const page = new URL(url).searchParams.get('page');
    return new Response(page === '1' ? ONE_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db } = makeDb({ links: [{ org_player_id: 'p1' }], rpcThrows: true });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures.length, 1);
    assertStringIncludes(failures[0], 'upsert 예외');
  });
});

// ── dedupeHistoryRows — 단체전 중복 행이 upsert 를 통째로 깨는 실측 버그 ──────
//
// 실측(2026-08-19, gjtennis.kr userid=nujani): 협회 원본이 같은 대회명+날짜를
// 부서="남자단체전"으로 3번 반복해서 준다. upsert_org_player_results 의 ON
// CONFLICT 대상은 (org_code, org_player_id, tournament_name, played_on) 이고
// event_raw(부서)는 안 걸려 있어, 한 INSERT 문 안에서 같은 대상을 두 번 이상
// 건드리면 Postgres 가 "ON CONFLICT DO UPDATE command cannot affect row a
// second time" 로 문장 전체를 롤백한다 — 그 선수의 전적이 하나도 안 쌓인다.

Deno.test('dedupeHistoryRows: 같은 (대회명, 대회일) 중복 행을 하나로 줄인다', () => {
  const rows = parsePlayerHistoryRows(`
    <table><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>다른대회</td><td>1</td><td>골드부</td><td>800</td><td>2026-05-09</td>
    </tr></table>`);
  assertEquals(rows.length, 4);
  const deduped = dedupeHistoryRows(rows);
  assertEquals(deduped.length, 2);
  assertEquals(deduped.map((r) => r.tournamentName).sort(), ['다른대회', '어등산클럽배']);
});

Deno.test('crawlPlayerHistories: 중복 행이 있어도 upsert 를 1번만 부르고 실패 없이 끝난다', async () => {
  const DUP_ROW_HTML = `
    <table><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>어등산클럽배</td><td>예선</td><td>남자단체전</td><td>10</td><td>2026-03-07</td>
    </tr><tr>
      <td>다른대회</td><td>1</td><td>골드부</td><td>800</td><td>2026-05-09</td>
    </tr></table>`;
  await withFetch((url) => {
    const page = new URL(url).searchParams.get('page');
    return new Response(page === '1' ? DUP_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'nujani' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(rpcCalls.length, 1);
    const args = rpcCalls[0].args as { p_rows: unknown[] };
    assertEquals(args.p_rows.length, 2); // 4행 → 중복 2행 제거 → 2행만 upsert
  });
});

// ── selectHistoryCandidates — confirmed 항상 포함 + 변경분/신규 상한 이월 ──────

Deno.test('selectHistoryCandidates: 신규(상태 없음) 선수는 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 100 }],
    state: [],
    cap: 10,
  });
  assertEquals(result, ['p1']);
});

Deno.test('selectHistoryCandidates: 포인트가 바뀐 선수는 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 200 }],
    state: [{ orgPlayerId: 'p1', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 10,
  });
  assertEquals(result, ['p1']);
});

Deno.test('selectHistoryCandidates: 포인트가 그대로면 제외된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 100 }],
    state: [{ orgPlayerId: 'p1', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 10,
  });
  assertEquals(result, []);
});

Deno.test('selectHistoryCandidates: confirmed 연결자는 변경 여부·상한과 무관하게 항상 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: ['pinned'],
    rankings: [{ orgPlayerId: 'pinned', totalPoints: 100 }],
    state: [{ orgPlayerId: 'pinned', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 0, // 상한을 0으로 줘도 confirmed 는 빠지지 않는다
  });
  assertEquals(result, ['pinned']);
});

Deno.test('selectHistoryCandidates: 상한을 넘는 변경분은 last_crawled_at 이 오래된(또는 없는) 순으로 남긴다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [
      { orgPlayerId: 'newer', totalPoints: 200 },
      { orgPlayerId: 'older', totalPoints: 300 },
      { orgPlayerId: 'brand-new', totalPoints: 50 },
    ],
    state: [
      { orgPlayerId: 'newer', lastPoints: 100, lastCrawledAt: '2026-08-24T00:00:00Z' },
      { orgPlayerId: 'older', lastPoints: 100, lastCrawledAt: '2026-08-01T00:00:00Z' },
      // brand-new 는 state 자체가 없다 — 가장 오래된 것으로 취급해 최우선.
    ],
    cap: 2,
  });
  assertEquals(result, ['brand-new', 'older']);
});

// ── fetchAllRows — PostgREST 1,000행 응답 상한 회피 페이지네이션 ──────

Deno.test('fetchAllRows: pageSize 보다 작은 페이지를 받으면 멈춘다 (전체 5건, 페이지 2건씩)', async () => {
  const all = ['a', 'b', 'c', 'd', 'e'];
  let calls = 0;
  const { rows, error } = await fetchAllRows<string>((from, to) => {
    calls++;
    return Promise.resolve({ data: all.slice(from, to + 1), error: null });
  }, 2);
  assertEquals(error, null);
  assertEquals(rows, all);
  assertEquals(calls, 3); // 2+2+1
});

Deno.test('fetchAllRows: 에러가 나면 그때까지 모은 것과 에러 메시지를 함께 돌려준다', async () => {
  let calls = 0;
  const { rows, error } = await fetchAllRows<string>((_from, _to) => {
    calls++;
    if (calls === 2) return Promise.resolve({ data: null, error: { message: 'boom' } });
    return Promise.resolve({ data: ['a', 'b'], error: null });
  }, 2);
  assertEquals(rows, ['a', 'b']);
  assertEquals(error, 'boom');
  assertEquals(calls, 2);
});

// ── crawlPlayerHistories 통합 — 랭킹표 기준 변경분/불변분 판정이 실제로 동작한다 ──

Deno.test('통합: 포인트가 바뀐 비연결 선수도 후보에 포함되어 크롤되고 상태가 기록된다', async () => {
  await withFetch((url) => {
    const page = new URL(url).searchParams.get('page');
    return new Response(page === '1' ? ONE_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({
      links: [],
      rankings: [{ org_player_id: 'newp', total_points: 500 }],
      state: [],
    });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    const fns = rpcCalls.map((c) => c.fn);
    assertEquals(fns.includes('upsert_org_player_results'), true);
    assertEquals(fns.includes('record_org_player_history_crawl_state'), true);
    const stateCall = rpcCalls.find((c) => c.fn === 'record_org_player_history_crawl_state');
    const stateArgs = stateCall?.args as { p_org_player_id: string; p_points: number };
    assertEquals(stateArgs.p_org_player_id, 'newp');
    assertEquals(stateArgs.p_points, 500);
  });
});

Deno.test('통합: 포인트가 그대로인 비연결 선수는 크롤되지 않는다(fetch 호출 없음)', async () => {
  let fetchCalls = 0;
  await withFetch(() => {
    fetchCalls++;
    return new Response(ONE_ROW_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({
      links: [],
      rankings: [{ org_player_id: 'samep', total_points: 100 }],
      state: [
        { org_player_id: 'samep', last_points: 100, last_crawled_at: '2026-08-20T00:00:00Z' },
      ],
    });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(fetchCalls, 0);
    assertEquals(rpcCalls.length, 0);
  });
});
