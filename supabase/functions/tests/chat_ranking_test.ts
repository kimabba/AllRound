import { assert, assertEquals, assertThrows } from 'std/assert/mod.ts';
import {
  type OrgPlayerLinkRow,
  type OrgRankingRow,
  parseOrgPlayerLinks,
  parseOrgRankingRows,
  rankingScopeLabel,
  renderMyRankingResults,
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

function playerLink(overrides: Partial<OrgPlayerLinkRow> = {}): OrgPlayerLinkRow {
  return {
    org_code: 'gj',
    org_player_id: 'peace1',
    user_id: 'user-1',
    status: 'confirmed',
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

Deno.test('외부 org_player_links JSON을 타입으로 좁히고 알 수 없는 상태는 거절한다', () => {
  assertEquals(parseOrgPlayerLinks([playerLink()]), [playerLink()]);
  assertThrows(
    () => parseOrgPlayerLinks([{ ...playerLink(), status: 'approved' }]),
    TypeError,
    'org_player_links[0]',
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

Deno.test('내 랭킹은 현재 사용자의 confirmed 연결만 조인해 렌더한다', () => {
  const rendered = renderMyRankingResults(
    [
      rankingRow(),
      rankingRow({ player_name: '다른사람', org_player_id: 'other-player', rank: 9 }),
    ],
    [
      playerLink(),
      playerLink({ org_player_id: 'other-player', user_id: 'user-2' }),
    ],
    'user-1',
  );
  assertEquals(
    rendered,
    [
      '내 현재 협회 랭킹입니다.',
      '- 1위 김평화 (어등산) · 순위포인트 2,649점 · 전체포인트 3,012점',
    ].join('\n'),
  );
});

Deno.test('내 랭킹은 pending, 미연결, 확정됐지만 빈 결과를 구분한다', () => {
  assertEquals(
    renderMyRankingResults([], [playerLink({ status: 'pending' })], 'user-1'),
    '본인 랭킹 연결 승인을 기다리고 있습니다. 승인되면 현재 순위와 포인트를 확인할 수 있습니다.',
  );
  assertEquals(
    renderMyRankingResults([], [], 'user-1'),
    '아직 본인으로 확정된 협회 랭킹이 없습니다. 랭킹 화면에서 본인 연결을 신청해 주세요.',
  );
  assertEquals(
    renderMyRankingResults([], [playerLink()], 'user-1'),
    '본인 연결은 확인됐지만 현재 협회 랭킹표에서 순위 정보를 찾지 못했습니다.',
  );
});

Deno.test('랭킹 라우팅은 임베딩보다 먼저 실행되고 본인 링크를 사용자 ID로 제한한다', async () => {
  const source = await Deno.readTextFile(new URL('../chat/index.ts', import.meta.url));
  const rankingRouteAt = source.indexOf('// ---- 협회 랭킹: DB 결정적 응답');
  const embeddingAt = source.indexOf('embedTextWithUsage(modelUserMessage');
  assert(rankingRouteAt >= 0);
  assert(embeddingAt > rankingRouteAt);
  assert(source.includes(".from('org_player_links')"));
  assert(source.includes(".eq('user_id', user.id)"));
  assert(source.includes("link.status === 'confirmed'"));
  assert(source.includes(".eq('org_code', link.org_code)"));
  assert(source.includes(".eq('org_player_id', link.org_player_id)"));
  assert(source.includes('embedTextWithUsage(modelUserMessage'));
  assert(source.includes(".select('role, content, citations')"));
  assert(source.includes('for (const m of modelPrior)'));
  assert(source.includes('slots: logSafeSlots(intentResult.slots)'));
});
