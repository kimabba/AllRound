// kato_parser_test.ts
// KATO parser 순수 파싱 함수 단위 테스트 (네트워크 없음, 인라인 픽스처).
// 픽스처는 kato.kr/openList·/openGame 실측 구조(2026-07)를 축약 반영.

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildTournament,
  katoCanonicalContent,
  type KatoDetailFields,
  type KatoListItem,
  parseKatoDetail,
  parseKatoListing,
} from '../_shared/crawler/parsers/kato_openlist.ts';
import { parseKatoRegulation } from '../_shared/crawler/parsers/kato_regulation.ts';
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

Deno.test('KATO canonical content: 조회수만 바뀌면 변경으로 보지 않는다', () => {
  const firstHtml = `${DETAIL_HTML}<span class="view-count">조회 10</span>`;
  const secondHtml = `${DETAIL_HTML}<span class="view-count">조회 11</span>`;
  const firstDetail = parseKatoDetail(firstHtml, '힌트제목') as KatoDetailFields;
  const secondDetail = parseKatoDetail(secondHtml, '힌트제목') as KatoDetailFields;

  assertEquals(
    katoCanonicalContent(firstHtml, firstDetail),
    katoCanonicalContent(secondHtml, secondDetail),
  );
});

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

// openGame/0299의 실제 DOM 구조를 축약한 회귀 픽스처.
// 운영 단체의 실계좌는 테스트 코드에 복제하지 않고 동일 형식의 가상 번호를 사용한다.
const KATO_0299_HTML = `
<div class="group-title">2026 낫소 KATO 회장배 전국동호인테니스대회</div>
<div id="tab1">
  <table class="table-bordered">
    <tr><td rowspan="11">일 시</td><td>국화부</td><td>2026년 08월 06일 (목) 09:00</td></tr>
    <tr><td>개나리부(공주)</td><td>2026년 08월 07일 (금) 09:00</td></tr>
    <tr><td>개나리부(서산,태안)</td><td>2026년 08월 07일 (금) 09:00</td></tr>
    <tr><td>개나리부(보령,홍성)</td><td>2026년 08월 07일 (금) 09:00</td></tr>
    <tr><td>개나리부(부여,청양)</td><td>2026년 08월 07일 (금) 09:00</td></tr>
    <tr><td>챌린저부(공주)</td><td>2026년 08월 08일 (토) 09:00</td></tr>
    <tr><td>챌린저부(서산,태안)</td><td>2026년 08월 08일 (토) 09:00</td></tr>
    <tr><td>챌린저부(보령,홍성)</td><td>2026년 08월 08일 (토) 09:00</td></tr>
    <tr><td>챌린저부(부여,청양)</td><td>2026년 08월 08일 (토) 09:00</td></tr>
    <tr><td>마스터스부</td><td>2026년 08월 09일 (일) 09:00</td></tr>
    <tr><td>베테랑부</td><td>2026년 08월 09일 (일) 09:00</td></tr>
    <tr><td>대회안내</td><td colspan="2">▣ 전경기 실내코트 진행 예정</td></tr>
    <tr><td>장 소</td><td colspan="2">▣국화부 : 공주시립 + 서산(태안)코트 진행</td></tr>
    <tr><td>주 최</td><td colspan="2">(사) 한국테니스발전협의회(KATO)</td></tr>
    <tr><td>주 관</td><td colspan="2">(사)한국테니스발전협의회(KATO)</td></tr>
    <tr><td>후 원</td><td colspan="2">(주)낫소</td></tr>
    <tr><td>협 찬</td><td colspan="2">(주)낫소, 나사라, 이브네</td></tr>
    <tr><td>사용구</td><td colspan="2">낫소 짜르투어 테니스볼</td></tr>
    <tr><td>환불마감</td><td colspan="2">▣ 접수개시일 : 여자부서 - 7월 13일 12시<br>▣ 취소 및 환불마감일 : 7월 30일 15시</td></tr>
    <tr><td>신청안내 및<br>입금계좌</td><td colspan="2">
      KATO 홈페이지 신청접수 www.kato.kr<br>
      참가자격문의: KATO사무국 02-401-7979<br>
      - 참가 접수 후 참가비 바로 입금 (대기자 참가비 절대 입금 금지)<br>
      * 출전선수는 생활체육 공제보험이나 상해보험에 반드시 가입<br>
      * 경기 촬영물의 초상권 및 관련 권리는 KATO에 귀속<br>
      ● 부서별 입금계좌 ●<br>
      ◑ 개나리부 ▶ 농협 355-0000-0001-11 한국테니스발전협의회<br>
      ◑ 국화부 ▶ 농협 355-0000-0002-22 한국테니스발전협의회<br>
      ◑ 챌린저부 ▶ 농협 355-0000-0003-33 한국테니스발전협의회<br>
      ◑ 마스터스부 ▶ 농협 355-0000-0004-44 한국테니스발전협의회<br>
      ◑ 베테랑부 ▶ 농협 355-0000-0005-55 한국테니스발전협의회
    </td></tr>
    <tr><td>참가비</td><td colspan="2">개인복식 팀당 64,000원</td></tr>
    <tr><td>참가상품</td><td colspan="2"><p>낫소제품</p></td></tr>
    <tr><td>시 상</td><td colspan="2">
      ◈ 개나리/챌린저부<br>* 우승 : 상패 및 시상금 220만원<br>
      ◈ 국화부/마스터스부/베테랑부<br>* 우승 : 상패 및 시상금 180만원<br>
      * 부서 80팀 미만 출전 시 시상금을 조정할 수 있음.
    </td></tr>
    <tr><td>감독관 및<br>문의처</td><td colspan="2">KATO 사무국 02-401-7979</td></tr>
    <tr><td>시드기준</td><td colspan="2">2025-07-01 ~ 2026-06-30</td></tr>
    <tr><td>출전규정</td><td colspan="2">전 종목 공통사항</td></tr>
  </table>
</div>
<div id="tab2"><table><tbody>
  <tr><td>국화부</td><td><div>2026년 08월 06일 (목) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>개나리부(공주)</td><td><div>2026년 08월 07일 (금) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>개나리부(서산,태안)</td><td><div>2026년 08월 07일 (금) 09:00</div><div class="place">서산시 종합운동장 테니스장</div></td><td>참가신청</td></tr>
  <tr><td>개나리부(보령,홍성)</td><td><div>2026년 08월 07일 (금) 09:00</div><div class="place">보령남포실내테니스장 외</div></td><td>참가신청</td></tr>
  <tr><td>개나리부(부여,청양)</td><td><div>2026년 08월 07일 (금) 09:00</div><div class="place">부여종합운동장 테니스장</div></td><td>참가신청</td></tr>
  <tr><td>챌린저부(공주)</td><td><div>2026년 08월 08일 (토) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>챌린저부(서산,태안)</td><td><div>2026년 08월 08일 (토) 09:00</div><div class="place">서산시 종합운동장 테니스장</div></td><td>참가신청</td></tr>
  <tr><td>챌린저부(보령,홍성)</td><td><div>2026년 08월 08일 (토) 09:00</div><div class="place">보령남포실내테니스장 외</div></td><td>참가신청</td></tr>
  <tr><td>챌린저부(부여,청양)</td><td><div>2026년 08월 08일 (토) 09:00</div><div class="place">부여종합운동장 테니스장</div></td><td>참가신청</td></tr>
  <tr><td>마스터스부</td><td><div>2026년 08월 09일 (일) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>베테랑부</td><td><div>2026년 08월 09일 (일) 09:00</div><div class="place">서산시 종합운동장 테니스장</div></td><td>참가신청</td></tr>
</tbody></table></div>`;

// openGame 실제 크롤분(2026-08-21) 3건을 축약·가공. 전화번호·계좌번호는 더미값으로 치환했다.
//
// 임실: 접수 개시 전(tab2 미오픈)이지만 tab1 요강은 완전 — '부서별 장소' 오탐 해소 검증.
const KATO_IMSIL_HTML = `
<div class="group-title">제14회 임실N치즈배 전국동호인테니스대회</div>
<div id="tab1">
  <table class="table-bordered">
    <tr><td rowspan="3">일 시</td><td>개나리부</td><td>2026년 10월 09일 (금) 09:00</td></tr>
    <tr><td>챌린저부</td><td>2026년 10월 10일 (토) 09:00</td></tr>
    <tr><td>국화부</td><td>2026년 10월 11일 (일) 09:00</td></tr>
    <tr><td>장 소</td><td colspan="2">임실군생활체육공원 테니스코트장외 전주완산체련공원테니스장</td></tr>
    <tr><td>접수개시 및<br>환불마감</td><td colspan="2">▣ 접수개시일 : 여자부서 - 9월 28일(월) 12시. 남자부서 - 9월 28일(월) 13시 ▣ 취소 및 환불마감일 : 10월 5일(월) 17시. 마감이후 환불불가.</td></tr>
    <tr><td>신청안내 및<br>입금계좌</td><td colspan="2">
      KATO 홈페이지 신청접수 www.kato.kr<br>
      ◈ 참가 접수 후 참가비 바로 입금 (대기자 절대 입금 금지!!)◈<br>
      개나리부 홍길동(010-0000-0001), 농협 000-0000-0001-01<br>
      챌린저부 김철수(010-0000-0002), 농협 000-0000-0002-02<br>
      국화부 이영희(010-0000-0003), 농협 000-0000-0003-03
    </td></tr>
    <tr><td>참가비</td><td colspan="2">개인복식 팀당 64,000원 [팀당 4천원 - 꿈나무육성기금]</td></tr>
    <tr><td>참가상품</td><td colspan="2"><p>치즈세트</p></td></tr>
    <tr><td>시 상</td><td colspan="2">
      ◈ 우 승 : 상패 및 현금 120만원<br>
      ◈ 준우승 : 상패 및 현금 80만원
    </td></tr>
  </table>
</div>
<div id="tab2"></div>`;

// 무령왕배: 접수 개시 후 tab2 정상 오픈 — 기존 coverage 검증 그대로(회귀 방지).
const KATO_MURYEONG_HTML = `
<div class="group-title">제16회 공주 무령왕배 전국동호인테니스대회</div>
<div id="tab1">
  <table class="table-bordered">
    <tr><td rowspan="4">일 시</td><td>개나리부</td><td>2026년 09월 17일 (목) 09:00</td></tr>
    <tr><td>국화부</td><td>2026년 09월 18일 (금) 09:00</td></tr>
    <tr><td>챌린저부</td><td>2026년 09월 19일 (토) 09:00</td></tr>
    <tr><td>마스터스부</td><td>2026년 09월 20일 (일) 09:00</td></tr>
    <tr><td>장 소</td><td colspan="2">공주시립테니스코트 외</td></tr>
    <tr><td>접수개시 및<br>환불마감</td><td colspan="2">▣ 접수개시일 : 2026년 8월 18일(화) 여자부서(12시)남자부서(13시) ▣ 취소 및 환불마감일 : 2026년 9월 10일(목) 15시마감</td></tr>
    <tr><td>신청안내 및<br>입금계좌</td><td colspan="2">
      KATO 홈페이지 신청접수 www.kato.kr<br>
      개나리부 홍길동, 농협 000-0000-0001-01<br>
      국화부 김철수, 농협 000-0000-0002-02<br>
      마스터스부 이영희, 농협 000-0000-0003-03<br>
      챌린저부 박민수, 농협 000-0000-0004-04
    </td></tr>
    <tr><td>참가비</td><td colspan="2">개인복식 팀당 64,000원 [팀당 4천원 - 꿈나무육성기금]</td></tr>
    <tr><td>참가상품</td><td colspan="2"><p>중식 식사권</p></td></tr>
    <tr><td>시 상</td><td colspan="2">
      ◈ 우 승 : 무령왕관 상패 및 상금 120만원<br>
      ◈ 준우승 : 고마곰인형 상패 및 상금 80만원
    </td></tr>
  </table>
</div>
<div id="tab2"><table><tbody>
  <tr><td>개나리부</td><td><div>2026년 09월 17일 (목) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>국화부</td><td><div>2026년 09월 18일 (금) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>챌린저부</td><td><div>2026년 09월 19일 (토) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
  <tr><td>마스터스부</td><td><div>2026년 09월 20일 (일) 09:00</div><div class="place">공주시립테니스코트</div></td><td>참가신청</td></tr>
</tbody></table></div>`;

// 서천군수배: tab2 미오픈 + tab1 요강 자체가 미기재('.') — 여전히 검수 대상이어야 한다.
const KATO_SEOCHEON_HTML = `
<div class="group-title">제4회 서천군수배 전국동호인테니스대회</div>
<div id="tab1">
  <table class="table-bordered">
    <tr><td rowspan="4">일 시</td><td>개나리부</td><td>2026년 10월 08일 (목) 09:00</td></tr>
    <tr><td>챌린저부</td><td>2026년 10월 09일 (금) 09:00</td></tr>
    <tr><td>혼합복식부</td><td>2026년 10월 10일 (토) 09:00</td></tr>
    <tr><td>베테랑부</td><td>2026년 10월 11일 (일) 09:00</td></tr>
    <tr><td>대회안내</td><td colspan="2">.</td></tr>
    <tr><td>장 소</td><td colspan="2">서천군 레포츠공원 테니스코트외 보조코트</td></tr>
    <tr><td>후 원</td><td colspan="2">.</td></tr>
    <tr><td>협 찬</td><td colspan="2">.</td></tr>
    <tr><td>접수개시 및<br>환불마감</td><td colspan="2">.</td></tr>
    <tr><td>신청안내 및<br>입금계좌</td><td colspan="2">.</td></tr>
    <tr><td>참가비</td><td colspan="2">.</td></tr>
    <tr><td>참가상품</td><td colspan="2"><p>.</p></td></tr>
    <tr><td>시 상</td><td colspan="2">.</td></tr>
  </table>
</div>
<div id="tab2"></div>`;

Deno.test('KATO 0299 회귀: 11개 부서 일정·장소와 5개 계좌·시상을 손실 없이 추출', () => {
  const regulation = parseKatoRegulation(KATO_0299_HTML);
  assert(regulation);
  assertEquals(regulation.coverage, {
    expectedDivisionCount: 11,
    parsedDivisionCount: 11,
    accountCount: 5,
    missingSections: [],
  });
  assertEquals(regulation.schedules.length, 11);
  assertEquals(regulation.location, '공주시립테니스코트 외 3곳');

  const scheduleField = regulation.fields.find((field) => field.label === '부서별 일정·장소');
  assert(
    scheduleField?.value.includes('국화부 · 2026년 08월 06일 (목) 09:00 · 공주시립테니스코트'),
  );
  assert(
    scheduleField?.value.includes(
      '베테랑부 · 2026년 08월 09일 (일) 09:00 · 서산시 종합운동장 테니스장',
    ),
  );
  assertEquals(scheduleField?.value.split('\n').length, 11);

  const accountField = regulation.fields.find((field) => field.label === '입금계좌');
  assertEquals(accountField?.value.split('\n').length, 5);
  assert(regulation.fields.some((field) => field.label === '접수·환불'));
  assert(
    regulation.fields.some((field) => field.label === '시상' && field.value.includes('220만원')),
  );
  assert(regulation.notes.some((note) => note.includes('상해보험')));
  assert(regulation.notes.some((note) => note.includes('80팀 미만')));
});

Deno.test('KATO 라벨 셀이 합쳐져 있어도 접수·환불을 찾는다', () => {
  // 공고마다 라벨 표기가 다르다. "환불마감" 단독인 곳도 있고 "접수개시 및<br>환불마감"
  // 인 곳도 있다(kato.kr/openGame/0307 실측). 정확매칭만 하면 값이 표에 있는데도
  // "빠진 섹션"으로 판정돼 요강 전체가 검수로 튕겨 정형화가 아예 안 된다.
  const merged = KATO_0299_HTML.replace(
    '<tr><td>환불마감</td>',
    '<tr><td>접수개시 및<br>환불마감</td>',
  );
  const regulation = parseKatoRegulation(merged);
  assert(regulation);
  assertEquals(regulation.coverage.missingSections, []);
  const refund = regulation.fields.find((field) => field.label === '접수·환불');
  assert(refund?.value.includes('7월 30일 15시'), '합쳐진 라벨에서도 값을 뽑아야 한다');
});

Deno.test('parseKatoDetail: 장소 값이 ▣로 시작해도 장소를 빈 값으로 버리지 않음', () => {
  const detail = parseKatoDetail(
    '<div class="group-title">테스트 대회</div><div id="tab1"><table>' +
      '<tr><td>장 소</td><td>▣국화부 : 공주시립 + 서산코트 진행</td></tr>' +
      '</table></div>',
    '힌트',
  );
  assertEquals(detail?.location, '공주시립 + 서산코트 진행');
});

Deno.test('KATO 요강 완전성 검사: tab2가 일부만 열려 있고 일부 부서 장소가 빠지면 여전히 검수 대상', () => {
  // tab2가 완전히 빈 경우(접수 개시 전)의 면제는 아래 '부서별 장소 면제' 테스트를 참고.
  // 여기서는 tab2가 열려 있는데(=접수 개시됨) 일부 부서만 장소가 비어 있는 진짜 파싱
  // 결함 시나리오이므로 기존과 동일하게 flag돼야 한다.
  const partiallyMissingPlace = KATO_0299_HTML.replace(
    '<tr><td>베테랑부</td><td><div>2026년 08월 09일 (일) 09:00</div><div class="place">서산시 종합운동장 테니스장</div></td><td>참가신청</td></tr>',
    '<tr><td>베테랑부</td><td><div>2026년 08월 09일 (일) 09:00</div></td><td>참가신청</td></tr>',
  );
  const regulation = parseKatoRegulation(partiallyMissingPlace);
  assert(regulation);
  assertEquals(regulation.coverage.expectedDivisionCount, 11);
  assertEquals(regulation.coverage.parsedDivisionCount, 10);
  assert(regulation.coverage.missingSections.includes('부서별 장소'));
});

Deno.test('KATO 부서별 장소 면제: 접수 개시 전 tab2 미오픈 + tab1 요강 완전(임실N치즈배) → 부서별 장소 요구 없음', () => {
  const regulation = parseKatoRegulation(KATO_IMSIL_HTML);
  assert(regulation);
  assertEquals(regulation.coverage.expectedDivisionCount, 3);
  assertEquals(regulation.coverage.parsedDivisionCount, 3);
  assertEquals(regulation.coverage.missingSections, []);
});

Deno.test('KATO 부서별 장소 면제 회귀: 접수 개시 후 tab2 정상 오픈(무령왕배)이면 기존과 동일하게 검증', () => {
  const regulation = parseKatoRegulation(KATO_MURYEONG_HTML);
  assert(regulation);
  assertEquals(regulation.coverage.expectedDivisionCount, 4);
  assertEquals(regulation.coverage.parsedDivisionCount, 4);
  assertEquals(regulation.coverage.missingSections, []);
  assertEquals(regulation.schedules.length, 4);
});

Deno.test('KATO 부서별 장소 면제 예외: #tab2 요소 자체가 없으면(마크업 드리프트) 면제하지 않는다', () => {
  const withoutTab2Element = KATO_IMSIL_HTML.replace('<div id="tab2"></div>', '');
  const regulation = parseKatoRegulation(withoutTab2Element);
  assert(regulation);
  assertEquals(regulation.coverage.expectedDivisionCount, 3);
  assertEquals(regulation.coverage.parsedDivisionCount, 0);
  assert(regulation.coverage.missingSections.includes('부서별 장소'));
});

Deno.test('KATO 부서별 장소 면제 예외: #tab2에 tr이 있는데 전부 파싱 실패면 면제하지 않는다', () => {
  const withUnparsableRows = KATO_IMSIL_HTML.replace(
    '<div id="tab2"></div>',
    '<div id="tab2"><table><tr><td>준비중</td></tr></table></div>',
  );
  const regulation = parseKatoRegulation(withUnparsableRows);
  assert(regulation);
  assertEquals(regulation.coverage.parsedDivisionCount, 0);
  assert(regulation.coverage.missingSections.includes('부서별 장소'));
});

Deno.test('KATO 부서별 장소 면제 예외: tab1 요강 자체가 미기재(서천군수배)면 여전히 검수 대상', () => {
  const regulation = parseKatoRegulation(KATO_SEOCHEON_HTML);
  assert(regulation);
  // '부서별 장소' 자체는 tab1 장소가 있으므로 면제되지만, 요강 미기재로 다른 섹션들이
  // 여전히 missing이라 전체적으로는 검수 대상에서 벗어나지 않는다.
  assertEquals(regulation.coverage.expectedDivisionCount, 4);
  assertEquals(regulation.coverage.parsedDivisionCount, 4);
  assert(!regulation.coverage.missingSections.includes('부서별 장소'));
  assertEquals(
    regulation.coverage.missingSections.sort(),
    ['시상', '입금계좌', '접수·환불', '참가비'].sort(),
  );
});

// 문경에이스배(d0cdec6a-46bf-4aac-a8c3-d57e4fc18140) 실측(2026-08-26) 축약. 계좌·전화는
// 더미값으로 치환하되 카카오뱅크(3333 시작 13자리)·토스뱅크(12자리) 형태는 유지 —
// 하이픈 없는 계좌가 '입금계좌' missing으로 오탐되던 문제(D조 검수 리포트)의 회귀 픽스처.
const KATO_MUNGYEONG_HTML = `
<div class="group-title">제1회 문경에이스배 전국동호인테니스대회</div>
<div id="tab1">
  <table class="table-bordered">
    <tr><td rowspan="3">일 시</td><td>개나리부</td><td>2026년 10월 04일 (일) 09:00</td></tr>
    <tr><td>챌린저부</td><td>2026년 10월 05일 (월) 09:00</td></tr>
    <tr><td>국화부</td><td>2026년 10월 05일 (월) 09:00</td></tr>
    <tr><td>장 소</td><td colspan="2">문경 영강테니스장 외</td></tr>
    <tr><td>접수개시 및<br>환불마감</td><td colspan="2">▣ 접수개시일 : 9월 4일(금) 12시 ▣ 환불마감 : 2026년 09월 30일(수) 18시</td></tr>
    <tr><td>신청안내 및<br>입금계좌</td><td colspan="2">
      KATO 홈페이지 신청접수 www.kato.kr<br>
      참가자격문의: KATO사무국 02-401-7979<br>
      ◈ 참가 접수 후 참가비 바로 입금 (대기자 절대 입금 금지!!)◈<br>
      개나리부(120팀)  3333000000001  (홍길동) 카카오뱅크<br>
      챌린저부(100팀) 3333000000002 (김철수) 카카오뱅크<br>
      국화부(80팀) 100000000001 (이영희) 토스뱅크
    </td></tr>
    <tr><td>참가비</td><td colspan="2">개인복식 팀당 54,000원</td></tr>
    <tr><td>시 상</td><td colspan="2">◈ 우 승 : 트로피, 상금 120만원</td></tr>
  </table>
</div>
<div id="tab2"></div>`;

const KATO_PHONE_ONLY_ACCOUNT_HTML = KATO_MUNGYEONG_HTML.replace(
  `      개나리부(120팀)  3333000000001  (홍길동) 카카오뱅크<br>
      챌린저부(100팀) 3333000000002 (김철수) 카카오뱅크<br>
      국화부(80팀) 100000000001 (이영희) 토스뱅크`,
  '      참가자격문의: 농협 01012345678',
);

Deno.test('KATO 하이픈 없는 계좌(카카오뱅크·토스뱅크식) 인식: 입금계좌 missing 오탐 해소', () => {
  const regulation = parseKatoRegulation(KATO_MUNGYEONG_HTML);
  assert(regulation);
  assertEquals(regulation.coverage.accountCount, 3);
  assert(!regulation.coverage.missingSections.includes('입금계좌'));
  const accountField = regulation.fields.find((field) => field.label === '입금계좌');
  assert(accountField?.value.includes('3333000000001'));
  assert(accountField?.value.includes('3333000000002'));
  assert(accountField?.value.includes('100000000001'));
});

Deno.test('KATO 전화번호(010 연속 11자리)만 있으면 계좌로 인정하지 않는다 (오인 방지)', () => {
  const regulation = parseKatoRegulation(KATO_PHONE_ONLY_ACCOUNT_HTML);
  assert(regulation);
  assertEquals(regulation.coverage.accountCount, 0);
  assert(regulation.coverage.missingSections.includes('입금계좌'));
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

Deno.test('buildTournament: description 미조립(undefined), 메타 필드는 유지', () => {
  const item: KatoListItem = {
    seq: '0289',
    url: 'https://kato.kr/openGame/0289',
    title: '제 6회 임사단배 전국동호인 테니스대회',
    partsText: '개나리부, 국화부',
    startDate: '2026-05-06',
    endDate: '2026-07-13',
    status: 'open',
  };
  const detail: KatoDetailFields = {
    title: '제 6회 임사단배 전국동호인 테니스대회',
    location: '공주시립실내테니스장',
    organizer: '(사) 한국테니스발전협의회(KATO)',
    entryFee: 64000,
  };
  const t = buildTournament(item, detail, [], '충남');

  assertEquals(t.description, undefined);
  // 메타 유지
  assertEquals(t.title, '제 6회 임사단배 전국동호인 테니스대회');
  assertEquals(t.start_date, '2026-05-06');
  assertEquals(t.end_date, '2026-07-13');
  assertEquals(t.region, '충남');
  assertEquals(t.location, '공주시립실내테니스장');
  assertEquals(t.eligible_grades, []);
  assertEquals(t.organizer, '(사) 한국테니스발전협의회(KATO)');
  assertEquals(t.entry_fee, 64000);
  assertEquals(t.source_url, 'https://kato.kr/openGame/0289');
});
