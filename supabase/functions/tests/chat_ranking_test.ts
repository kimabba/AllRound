import { assert, assertEquals, assertThrows } from 'std/assert/mod.ts';
import {
  type OrgRankingRow,
  parseOrgRankingRows,
  rankingScopeLabel,
  renderRankingResults,
} from '../chat/ranking.ts';

function rankingRow(overrides: Partial<OrgRankingRow> = {}): OrgRankingRow {
  return {
    org_code: 'gj',
    division_code: 'gj_m_gold',
    rank: 1,
    player_name: '김평화',
    org_player_id: 'peace1',
    club_raw: '어등산/',
    rank_points: 2649,
    total_points: 3012,
    ...overrides,
  };
}

Deno.test('외부 org_rankings JSON을 타입으로 좁히고 잘못된 행은 거절한다', () => {
  const raw: unknown = [{
    org_code: 'gj',
    division_code: 'gj_m_gold',
    rank: 1,
    player_name: ' 김평화 ',
    org_player_id: 'peace1',
    club_raw: '어등산/',
    rank_points: 2649,
    total_points: 3012,
  }];
  assertEquals(parseOrgRankingRows(raw), [rankingRow()]);
  assertThrows(
    () => parseOrgRankingRows([{ ...rankingRow(), rank_points: '2649' }]),
    TypeError,
    'org_rankings[0]',
  );
  assertThrows(
    () => parseOrgRankingRows([{ ...rankingRow(), division_code: 'jn_m_gold' }]),
    TypeError,
    'org_rankings[0]',
  );
});

Deno.test('일반 랭킹은 협회 공표 순위와 두 포인트를 구분해 읽기 좋게 렌더한다', () => {
  const rendered = renderRankingResults([
    rankingRow({ rank: 3, player_name: '기주형', org_player_id: 'player2', rank_points: 1688 }),
    rankingRow(),
  ], {
    orgCode: 'gj',
    divisionCode: 'gj_m_gold',
  });
  assertEquals(
    rendered,
    [
      '광주광역시테니스협회 골드부 현재 랭킹입니다.',
      '- 1위 김평화 (어등산) · 순위포인트 2,649점 · 전체포인트 3,012점',
      '- 3위 기주형 (어등산) · 순위포인트 1,688점 · 전체포인트 3,012점',
    ].join('\n'),
  );
});

Deno.test('랭킹 출처 제목은 내부 부서 코드 대신 사용자용 라벨을 쓴다', () => {
  assertEquals(rankingScopeLabel('gj', 'gj_m_gold'), '광주광역시테니스협회 골드부');
});

Deno.test('동일 협회·부서에서 같은 공표 순위가 반복되면 공동 순위로 표시한다', () => {
  const rendered = renderRankingResults([
    rankingRow({ rank: 2, player_name: '김평화' }),
    rankingRow({ rank: 2, player_name: '박사랑', org_player_id: 'love2' }),
    rankingRow({ rank: 4, player_name: '이정직', org_player_id: 'honest3' }),
  ]);
  assertEquals(rendered.includes('- 공동 2위 김평화'), true);
  assertEquals(rendered.includes('- 공동 2위 박사랑'), true);
  assertEquals(rendered.includes('- 4위 이정직'), true);
});

Deno.test('일반 랭킹 빈 결과는 조회 조건을 포함해 추측 없이 안내한다', () => {
  assertEquals(
    renderRankingResults([], {
      orgCode: 'jn',
      divisionCode: 'jn_w_rookie',
      playerName: '없는선수',
    }),
    '전라남도테니스협회 여자신인부 없는선수 선수의 현재 랭킹 결과가 없습니다.',
  );
  assertEquals(renderRankingResults([]), '조건에 맞는 현재 협회 랭킹 결과가 없습니다.');
});

Deno.test('랭킹 조회 라우팅은 임베딩보다 먼저 실행된다', async () => {
  // "본인 랭킹"은 여기서 다루지 않는다 — #424가 이미 my_profile 라우팅에
  // my_confirmed_ranking RPC로 통합해뒀다. 이 파일이 다루는 ranking_lookup은
  // 공개 랭킹(협회/부서/선수명 조회)만 본다.
  const source = await Deno.readTextFile(new URL('../chat/index.ts', import.meta.url));
  const rankingRouteAt = source.indexOf('// ---- 협회 랭킹 조회: DB 결정적 응답');
  const embeddingAt = source.indexOf('embedTextWithUsage(modelUserMessage');
  assert(rankingRouteAt >= 0);
  assert(embeddingAt > rankingRouteAt);
  assert(source.includes("initialRuleHit?.intent === 'ranking_lookup'"));
  assert(source.includes('embedTextWithUsage(modelUserMessage'));
  assert(source.includes(".select('role, content, citations')"));
  assert(source.includes('for (const m of modelPrior)'));
  assert(source.includes('slots: logSafeSlots(intentResult.slots)'));
});
