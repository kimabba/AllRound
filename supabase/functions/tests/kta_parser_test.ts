// kta_parser_test.ts
// KTA(대한테니스협회) sportsForAll parser 순수 파싱 함수 단위 테스트.
// 픽스처는 join.kortennis.or.kr 의 sportsForAll_selList.json(listing) /
// sportsForAll_selEventInfoList.json(상세) 실측 응답(2026-08-19)을 축약 반영.

import { assertEquals } from 'std/assert/mod.ts';
import {
  buildTournament,
  extractPosterUrl,
  mergeDivisionDicts,
  parseKtaDate,
  parseKtaListRows,
} from '../_shared/crawler/parsers/kta_sportsforall.ts';

Deno.test('parseKtaDate: 요일 괄호가 붙어도 날짜만 추출한다', () => {
  assertEquals(parseKtaDate('2026.10.03(토)'), '2026-10-03');
  assertEquals(parseKtaDate('2026.09.30(수)'), '2026-09-30');
  assertEquals(parseKtaDate(null), null);
  assertEquals(parseKtaDate(''), null);
  assertEquals(parseKtaDate('날짜없음'), null);
});

Deno.test('parseKtaListRows: 정상 row 매핑 + 상세 URL 조립', () => {
  const rows = [
    {
      placeSeq: null,
      applEndDt: '2026.09.30(수)',
      cmptEvntCd: '202600202',
      cmptStrDt: '2026.10.03(토)',
      cmptNm: '2026 경북영일만 전국동호인테니스대회(CA그룹: 감독관 김경섭)',
      applStrDt: '2026.08.14(금)',
      applCnt: '0 / 0',
      dtlSt: '접수 중',
      placeNm: null,
      cmptEndDt: '2026.10.05(월)',
    },
  ];
  const items = parseKtaListRows(rows);
  assertEquals(items.length, 1);
  assertEquals(items[0].title, '2026 경북영일만 전국동호인테니스대회(CA그룹: 감독관 김경섭)');
  assertEquals(items[0].startDate, '2026-10-03');
  assertEquals(items[0].endDate, '2026-10-05');
  assertEquals(items[0].applicationDeadline, '2026-09-30');
  assertEquals(items[0].location, null);
  assertEquals(items[0].ended, false);
  assertEquals(
    items[0].url,
    'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd=202600202&dtlSt=Tab1',
  );
});

Deno.test('parseKtaListRows: dtlSt 에 "종료" 가 포함되면 ended=true', () => {
  const rows = [
    {
      cmptEvntCd: '1',
      cmptNm: '종료된 대회',
      cmptStrDt: '2026.01.01(목)',
      dtlSt: '대회종료',
    } as never,
    {
      cmptEvntCd: '2',
      cmptNm: '진행중인 대회',
      cmptStrDt: '2026.01.01(목)',
      dtlSt: '진행 중',
    } as never,
  ];
  const items = parseKtaListRows(rows);
  assertEquals(items.find((i) => i.cmptEvntCd === '1')?.ended, true);
  assertEquals(items.find((i) => i.cmptEvntCd === '2')?.ended, false);
});

Deno.test('parseKtaListRows: placeNm 이 있으면 location 으로 채운다', () => {
  const rows = [
    {
      placeSeq: '1',
      applEndDt: null,
      cmptEvntCd: '202600300',
      cmptStrDt: '2026.11.01(일)',
      cmptNm: '테스트 대회',
      applStrDt: null,
      applCnt: null,
      dtlSt: null,
      placeNm: '올림픽공원 테니스경기장',
      cmptEndDt: null,
    },
  ];
  assertEquals(parseKtaListRows(rows)[0].location, '올림픽공원 테니스경기장');
});

Deno.test('parseKtaListRows: cmptStrDt 없는 row/제목 없는 row/중복 cmptEvntCd 는 스킵', () => {
  const rows = [
    { cmptEvntCd: '1', cmptNm: '제목', cmptStrDt: null } as never,
    { cmptEvntCd: '2', cmptNm: '', cmptStrDt: '2026.01.01(목)' } as never,
    { cmptEvntCd: '', cmptNm: '제목', cmptStrDt: '2026.01.01(목)' } as never,
    { cmptEvntCd: '3', cmptNm: '중복1', cmptStrDt: '2026.01.01(목)' } as never,
    { cmptEvntCd: '3', cmptNm: '중복2', cmptStrDt: '2026.01.02(금)' } as never,
  ];
  const items = parseKtaListRows(rows);
  assertEquals(items.length, 1);
  assertEquals(items[0].cmptEvntCd, '3');
  assertEquals(items[0].title, '중복1'); // 먼저 나온 행이 채택된다
});

Deno.test('buildTournament: 상세 없음(detail=null) → listing location 으로 fallback, 부서 미매칭이면 eligible_grades=[]', () => {
  const item = {
    cmptEvntCd: '202600202',
    title: '2026 경북영일만 전국동호인테니스대회',
    startDate: '2026-10-03',
    endDate: '2026-10-05',
    applicationDeadline: '2026-09-30',
    location: null,
    ended: false,
    url:
      'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd=202600202&dtlSt=Tab1',
  };
  const t = buildTournament(item, null, [], null);
  assertEquals(t.title, item.title);
  assertEquals(t.start_date, '2026-10-03');
  assertEquals(t.end_date, '2026-10-05');
  assertEquals(t.application_deadline, '2026-09-30');
  assertEquals(t.region, undefined);
  assertEquals(t.location, undefined);
  assertEquals(t.organizer, undefined);
  assertEquals(t.eligible_grades, []);
  assertEquals(t.source_url, item.url);
});

Deno.test('buildTournament: 상세의 장소/주최가 listing 값보다 우선한다', () => {
  const item = {
    cmptEvntCd: '202600202',
    title: '2026 경북영일만 전국동호인테니스대회',
    startDate: '2026-10-03',
    endDate: '2026-10-05',
    applicationDeadline: '2026-09-30',
    location: 'listing 장소',
    ended: false,
    url: 'https://join.kortennis.or.kr/...&cmptEvntCd=202600202',
  };
  const detail = {
    location: '포항시 뱃머리테니스장 외 보조경기장',
    organizer: '(사)대한테니스협회, 경상북도테니스협회',
    divisionText: '',
    posterUrl: 'https://join.kortennis.or.kr/upload/editor/2026/08/1786519819832.png',
  };
  const t = buildTournament(item, detail, [], null);
  assertEquals(t.location, '포항시 뱃머리테니스장 외 보조경기장');
  assertEquals(t.organizer, '(사)대한테니스협회, 경상북도테니스협회');
  assertEquals(
    t.poster_url,
    'https://join.kortennis.or.kr/upload/editor/2026/08/1786519819832.png',
  );
});

Deno.test('buildTournament: 부서명이 title 이 아니라 상세 divisionText 안에만 있어도 매칭한다', () => {
  // 실측(cmptEvntCd=202600202): entryFeeTxt 안에 "1. 개나리부 ... 2. 챌린저부 ... 3. 국화부 ..."
  // 처럼 부서명이 자유 텍스트로 섞여 나온다 — listing/title 에는 부서 정보가 없다.
  // (fetchEventDetail 은 이 텍스트를 entryFeeTxt/partAppl/awardTxt/contactUs 네 필드를
  //  이어붙여 만든다 — 대회마다 부서명이 다른 필드에 나오기 때문. 여기선 이미 이어붙여진
  //  divisionText 값만으로 매칭을 검증한다.)
  const item = {
    cmptEvntCd: '202600202',
    title: '2026 경북영일만 전국동호인테니스대회(CA그룹: 감독관 김경섭)',
    startDate: '2026-10-03',
    endDate: '2026-10-05',
    applicationDeadline: '2026-09-30',
    location: null,
    ended: false,
    url: 'https://join.kortennis.or.kr/...&cmptEvntCd=202600202',
  };
  const detail = {
    location: '포항시 뱃머리테니스장 외 보조경기장',
    organizer: null,
    divisionText: '1. 개나리부 최영진 010-2820-5545 카카오뱅 최선은 3333-13-5778390 ' +
      '2. 챌린저부 이상윤 010-3521-9340 카카오뱅크 배상호 3333-37-8813328 ' +
      '3. 국화부 최영진 010-2820-5545 신한 배상호 805-04-055652',
    posterUrl: null,
  };
  const dict = [
    { code: 'kato_gaenari', synonyms: ['개나리부', '개나리'], label_ko: '개나리부' },
    { code: 'kato_challenger', synonyms: ['챌린저부', '챌린저'], label_ko: '챌린저부' },
    { code: 'kato_gukhwa', synonyms: ['국화부', '국화'], label_ko: '국화부' },
  ];
  const t = buildTournament(item, detail, dict, null);
  assertEquals(t.eligible_grades, ['kato_gaenari', 'kato_challenger', 'kato_gukhwa']);
  assertEquals(t.division_label_local, '개나리부 · 챌린저부 · 국화부');
});

Deno.test('mergeDivisionDicts: code 기준으로 합치고 중복은 먼저 온 사전을 우선한다', () => {
  const kta = [
    { code: 'kta_m_open', synonyms: ['남자오픈'], label_ko: '남자오픈' },
    { code: 'kstf_60', synonyms: ['어르신60+'], label_ko: '60+부(kta판)' },
  ];
  const kato = [
    { code: 'kato_gaenari', synonyms: ['개나리부'], label_ko: '개나리부' },
    { code: 'kstf_60', synonyms: ['60대'], label_ko: '60+부(kato판)' },
  ];
  const merged = mergeDivisionDicts(kta, kato);
  assertEquals(merged.map((r) => r.code).sort(), ['kato_gaenari', 'kstf_60', 'kta_m_open']);
  // 중복 code('kstf_60')는 먼저 넘긴 kta 쪽 행이 채택된다.
  assertEquals(merged.find((r) => r.code === 'kstf_60')?.label_ko, '60+부(kta판)');
});

Deno.test('extractPosterUrl: 요강 본문의 첫 <img> src 를 절대경로로 뽑는다', () => {
  assertEquals(
    extractPosterUrl(
      '<p><img src="/upload/editor/2026/08/1786519819832.png" style="width: 823px;"></p>' +
        '<p><img src="/upload/editor/2026/08/1786519838119.png"><br></p>',
    ),
    'https://join.kortennis.or.kr/upload/editor/2026/08/1786519819832.png',
  );
  assertEquals(extractPosterUrl('<p>이미지 없음</p>'), null);
  assertEquals(extractPosterUrl(null), null);
  assertEquals(extractPosterUrl(''), null);
});
