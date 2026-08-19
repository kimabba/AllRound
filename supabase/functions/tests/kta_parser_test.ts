// kta_parser_test.ts
// KTA(대한테니스협회) sportsForAll parser 순수 파싱 함수 단위 테스트.
// 픽스처는 join.kortennis.or.kr/sportsForAll_selList.json 실측 응답(2026-08-19)을 축약 반영.

import { assertEquals } from 'std/assert/mod.ts';
import {
  buildTournament,
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
  assertEquals(
    items[0].url,
    'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd=202600202&dtlSt=Tab1',
  );
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

Deno.test('buildTournament: 메타 필드 매핑, 부서 미매칭이면 eligible_grades=[]', () => {
  const item = {
    cmptEvntCd: '202600202',
    title: '2026 경북영일만 전국동호인테니스대회',
    startDate: '2026-10-03',
    endDate: '2026-10-05',
    applicationDeadline: '2026-09-30',
    location: null,
    url:
      'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd=202600202&dtlSt=Tab1',
  };
  const t = buildTournament(item, [], null);
  assertEquals(t.title, item.title);
  assertEquals(t.start_date, '2026-10-03');
  assertEquals(t.end_date, '2026-10-05');
  assertEquals(t.application_deadline, '2026-09-30');
  assertEquals(t.region, undefined);
  assertEquals(t.location, undefined);
  assertEquals(t.eligible_grades, []);
  assertEquals(t.source_url, item.url);
});

Deno.test('buildTournament: dict 매칭 시 eligible_grades/division_label_local 채움', () => {
  const item = {
    cmptEvntCd: '202600203',
    title: '2026 마스터스부 초청 테니스대회',
    startDate: '2026-11-01',
    endDate: null,
    applicationDeadline: null,
    location: '서울 테니스경기장',
    url:
      'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do?cmptEvntCd=202600203&dtlSt=Tab1',
  };
  const dict = [
    { code: 'kta_masters', synonyms: ['마스터스부', '마스터스'], label_ko: '마스터스부' },
  ];
  const t = buildTournament(item, dict, null);
  assertEquals(t.eligible_grades, ['kta_masters']);
  assertEquals(t.division_label_local, '마스터스부');
  assertEquals(t.location, '서울 테니스경기장');
});
