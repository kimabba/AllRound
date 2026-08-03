import { assertEquals } from 'std/assert/mod.ts';
import {
  normalizeResultRound,
  parsePlayerHistoryRows,
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
