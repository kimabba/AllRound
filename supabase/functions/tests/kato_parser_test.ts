// kato_parser_test.ts
// KATO parser 순수 파싱 함수 단위 테스트 (네트워크 없음, 인라인 픽스처).
// 픽스처는 kato.kr/openList·/openGame 실측 구조(2026-07)를 축약 반영.

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  type KatoDetailFields,
  type KatoListItem,
  parseKatoDetail,
  parseKatoListing,
} from '../_shared/crawler/parsers/kato_openlist.ts';
import { mapDivisionsByDict } from '../_shared/crawler/divisions.ts';

const BASE = 'https://kato.kr/openList';

// 대회 2건: 종료(comgray) 1 + 접수중(comblue) 1.
const LISTING_HTML = `
<div class="view-port">
  <div class="month-sector">2026년 01월</div>
  <div class="content-sector">
    <table><tr>
      <td class="group-sector"><img src="/assets/images/system/groupma_60.png" /></td>
      <td class="title-sector">
        <div class="title"><a href="/openGame/0271" class="content-title">제23회 서귀포칠십리 전국동호인테니스대회</a></div>
        <div class="area"><span class="parts">혼합복식부, 챌린저부, 마스터스부, 국화부, 개나리부</span></div>
        <div class="date">2026.01.21 ~ 2026.01.25</div>
      </td>
      <td class="part-sector"><div class="each"><a href="/openGame/0271"><span class="comgray">대회종료</span></a></div></td>
    </tr></table>
  </div>
  <div class="month-sector">2026년 05월</div>
  <div class="content-sector">
    <table><tr>
      <td class="group-sector"><img src="/assets/images/system/group3_60.png" /></td>
      <td class="title-sector">
        <div class="title"><a href="/openGame/0289" class="content-title">제 6회 임사단배 전국동호인 테니스대회</a></div>
        <div class="area"><span class="parts">개나리부, 국화부</span></div>
        <div class="date">2026.05.06 ~ 2026.07.13</div>
      </td>
      <td class="part-sector"><div class="each"><a href="/openGame/0289"><span class="comblue">대회접수중</span></a></div></td>
    </tr></table>
  </div>
</div>`;

Deno.test('parseKatoListing: 대회 2건 추출 + 상태/날짜/부서 파싱', () => {
  const items = parseKatoListing(LISTING_HTML, BASE);
  assertEquals(items.length, 2);

  const ended = items.find((i) => i.seq === '0271') as KatoListItem;
  assertEquals(ended.status, 'ended');
  assertEquals(ended.startDate, '2026-01-21');
  assertEquals(ended.endDate, '2026-01-25');
  assertEquals(ended.url, 'https://kato.kr/openGame/0271');
  assert(ended.partsText.includes('챌린저부'));

  const open = items.find((i) => i.seq === '0289') as KatoListItem;
  assertEquals(open.status, 'open');
  assertEquals(open.startDate, '2026-05-06');
  assertEquals(open.endDate, '2026-07-13');
  assertEquals(open.title, '제 6회 임사단배 전국동호인 테니스대회');
});

Deno.test('parseKatoListing: 중복 seq 는 1건만', () => {
  const dup = LISTING_HTML + LISTING_HTML;
  const items = parseKatoListing(dup, BASE);
  assertEquals(items.length, 2);
});

const DETAIL_HTML = `
<div class="group-title">제 6회 임사단배 전국동호인 테니스대회</div>
<div class="competition-group">2026 KATO랭킹 3그룹</div>
<table>
  <tr><td>대회명</td><td colspan="2">제 6회 임사단배</td></tr>
  <tr><td>장 소</td><td colspan="2">오산시립테니스장, 충주 탄금대 테니스장 ▣ 개나리부 안내</td></tr>
  <tr><td>주 최</td><td colspan="2">임사단</td></tr>
  <tr><td>주 관</td><td colspan="2">(사)한국테니스발전협의회(KATO)</td></tr>
  <tr><td>참가비</td><td colspan="2">개인복식 팀당 64,000원 [팀당 4천원 - 꿈나무육성기금]</td></tr>
</table>`;

Deno.test('parseKatoDetail: group-title·장소·주최·참가비 추출 (전각공백 라벨)', () => {
  const d = parseKatoDetail(DETAIL_HTML, '힌트제목') as KatoDetailFields;
  assertEquals(d.title, '제 6회 임사단배 전국동호인 테니스대회');
  // 장소는 ▣ 이후 부서주석을 잘라낸다
  assertEquals(d.location, '오산시립테니스장, 충주 탄금대 테니스장');
  assertEquals(d.organizer, '임사단');
  assertEquals(d.entryFee, 64000);
});

Deno.test('parseKatoDetail: group-title 없으면 titleHint 사용', () => {
  const d = parseKatoDetail(
    '<table><tr><td>주 최</td><td>협회</td></tr></table>',
    '리스트제목',
  ) as KatoDetailFields;
  assertEquals(d.title, '리스트제목');
  assertEquals(d.organizer, '협회');
  assertEquals(d.entryFee, undefined);
});

Deno.test('KATO 부서 매핑: span.parts 텍스트 → kato_* codes', () => {
  // seed 와 동일한 최소 사전(부분)으로 매핑 동작 확인.
  const dict = [
    { code: 'kato_gaenari', synonyms: ['개나리부', '개나리'], label_ko: '개나리부' },
    { code: 'kato_gukhwa', synonyms: ['국화부', '국화'], label_ko: '국화부' },
    { code: 'kato_challenger', synonyms: ['챌린저부', '챌린저'], label_ko: '챌린저부' },
  ];
  const { codes } = mapDivisionsByDict('혼합복식부, 챌린저부, 마스터스부, 국화부, 개나리부', dict);
  assertEquals(codes.sort(), ['kato_challenger', 'kato_gaenari', 'kato_gukhwa']);
});
