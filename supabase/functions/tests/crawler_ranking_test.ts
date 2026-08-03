import { assertEquals } from 'jsr:@std/assert';
import { parseRankingRows } from '../_shared/crawler/parsers/gnuboard_ranking.ts';

const html = await Deno.readTextFile(
  new URL('./fixtures/gj_ranking_gold.html', import.meta.url),
);

Deno.test('랭킹표 행을 파싱한다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows[0].rank, 1);
  assertEquals(rows[0].playerName, '김평화');
  assertEquals(rows[0].orgPlayerId, 'vudghk2116');
  assertEquals(rows[0].clubRaw, '어등산/');
});

Deno.test('천 단위 콤마를 제거하고 숫자로 만든다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows[0].rankPoints, 2649);
  assertEquals(rows[0].totalPoints, 2649);
});

Deno.test('순위포인트와 전체포인트를 순서로 구분한다 (같은 data-table 값)', () => {
  const twoCells = `
    <table class="list_tb">
    <tr>
      <td data-table="wr_1">7</td>
      <td data-table="wr_2">골드부</td>
      <td data-table="wr_3"></td>
      <td data-table="wr_4"><a href="javascript:player_rank('abc','골드부')"><b>홍길동</b></a></td>
      <td data-table="wr_5">클럽/</td>
      <td data-table="wr_6">1,000</td>
      <td data-table="wr_6">2,000</td>
    </tr>
    </table>`;
  const rows = parseRankingRows(twoCells);
  assertEquals(rows[0].rankPoints, 1000);
  assertEquals(rows[0].totalPoints, 2000);
});

Deno.test('0점 선수도 파싱은 한다 (필터는 상위 계층 책임)', () => {
  const rows = parseRankingRows(html);
  const zeros = rows.filter((r) => r.totalPoints === 0);
  assertEquals(zeros.length > 0, true);
});

Deno.test('사진 링크가 없어도 성명 셀에서 아이디를 뽑는다', () => {
  const noPhoto = `
    <table class="list_tb">
    <tr>
      <td data-table="wr_1">9</td>
      <td data-table="wr_2">골드부</td>
      <td data-table="wr_3"></td>
      <td data-table="wr_4"><a href="javascript:player_rank('nophoto','골드부')"><b>사진없음</b></a></td>
      <td data-table="wr_5"></td>
      <td data-table="wr_6">10</td>
      <td data-table="wr_6">10</td>
    </tr>
    </table>`;
  const rows = parseRankingRows(noPhoto);
  assertEquals(rows[0].orgPlayerId, 'nophoto');
  assertEquals(rows[0].clubRaw, null);
});

Deno.test('헤더 행은 건너뛴다', () => {
  const rows = parseRankingRows(html);
  assertEquals(rows.every((r) => Number.isInteger(r.rank) && r.rank > 0), true);
});
