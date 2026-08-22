import { assertEquals } from 'std/assert/mod.ts';
import { parsePlayerHistoryParams } from '../ranking-player-history/validation.ts';

Deno.test('선수 이력 파라미터는 지원 협회와 안전한 선수 ID만 허용한다', () => {
  const parsed = parsePlayerHistoryParams(
    new URL('https://example.test?org=gj&player_id=player_123-xy'),
  );
  assertEquals(parsed, { orgCode: 'gj', orgPlayerId: 'player_123-xy' });
});

Deno.test('선수 이력 파라미터는 임의 협회와 경로 문자를 거부한다', () => {
  assertEquals(
    parsePlayerHistoryParams(
      new URL('https://example.test?org=kta&player_id=player1'),
    ),
    null,
  );
  assertEquals(
    parsePlayerHistoryParams(
      new URL('https://example.test?org=gj&player_id=../../secret'),
    ),
    null,
  );
});
