// kato_parser_test.ts
// KATO parser 순수 파싱 함수 단위 테스트 (네트워크 없음, 인라인 픽스처).
// 픽스처는 kato.kr/openList·/openGame 실측 구조(2026-07)를 축약 반영.

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildTournament,
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

Deno.test('parseKatoDetail: 장소 값이 ▣로 시작해도 장소를 빈 값으로 버리지 않음', () => {
  const detail = parseKatoDetail(
    '<div class="group-title">테스트 대회</div><div id="tab1"><table>' +
      '<tr><td>장 소</td><td>▣국화부 : 공주시립 + 서산코트 진행</td></tr>' +
      '</table></div>',
    '힌트',
  );
  assertEquals(detail?.location, '공주시립 + 서산코트 진행');
});

Deno.test('KATO 요강 완전성 검사: 부서별 경기장 표가 빠지면 검수 대상으로 표시', () => {
  const withoutApplicationTab = KATO_0299_HTML.replace(/<div id="tab2">[\s\S]*$/, '');
  const regulation = parseKatoRegulation(withoutApplicationTab);
  assert(regulation);
  assertEquals(regulation.coverage.expectedDivisionCount, 11);
  assertEquals(regulation.coverage.parsedDivisionCount, 0);
  assert(regulation.coverage.missingSections.includes('부서별 장소'));
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
