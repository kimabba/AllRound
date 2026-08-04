import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';
import {
  crawlPlayerHistories,
  looksLikeHistoryPage,
  normalizeResultRound,
  parsePlayerHistoryRows,
  playerHistoryUrl,
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
  fromThrows?: boolean;
  rpcThrows?: boolean;
}): { db: SupabaseLike; rpcCalls: unknown[] } {
  const rpcCalls: unknown[] = [];
  const db: SupabaseLike = {
    from() {
      if (opts.fromThrows) throw new Error('boom: from');
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
    },
    rpc(_fn, args) {
      if (opts.rpcThrows) throw new Error('boom: rpc');
      rpcCalls.push(args);
      return Promise.resolve({ error: null });
    },
  };
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
    assertEquals(failures.length, 1);
    assertStringIncludes(failures[0], '1페이지 파싱 0행');
    assertStringIncludes(failures[0], '표 헤더 없음');
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

Deno.test('둘째 페이지부터의 0행은 정상 종료다 — failures 에 남지 않는다', async () => {
  let call = 0;
  await withFetch(() => {
    call++;
    return new Response(call === 1 ? ONE_ROW_HTML : ZERO_ROW_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({ links: [{ org_player_id: 'p1' }] });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(rpcCalls.length, 1);
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
    return new Response(page === '1' ? ONE_ROW_HTML : ZERO_ROW_HTML, { status: 200 });
  }, async () => {
    const { db } = makeDb({ links: [{ org_player_id: 'p1' }], rpcThrows: true });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures.length, 1);
    assertStringIncludes(failures[0], 'upsert 예외');
  });
});
