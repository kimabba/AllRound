export interface PlayerHistoryParams {
  orgCode: 'gj' | 'jn';
  orgPlayerId: string;
}

const PLAYER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export function parsePlayerHistoryParams(url: URL): PlayerHistoryParams | null {
  const org = url.searchParams.get('org');
  const playerId = url.searchParams.get('player_id');
  if ((org !== 'gj' && org !== 'jn') || !playerId || !PLAYER_ID_PATTERN.test(playerId)) {
    return null;
  }
  return { orgCode: org, orgPlayerId: playerId };
}
