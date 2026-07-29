// 광주 구별 협회(표준 그누보드) 회귀 가드.
//
// 시협회·전남은 커스텀 템플릿(sub5_2_2.php?sid=), 구 협회 넷은 표준 그누보드
// (bbs/board.php?bo_table=game&wr_id=)다. 한 파서가 둘을 다 받으므로, 한쪽을
// 고치다 다른 쪽을 깨뜨리는 일이 실제로 일어났다 — 아래 테스트가 그 지점들을 고정한다.
//
// 픽스처는 실물 구조를 모사한다(2026-07-29~30 수집):
//   coach.gjtennis.kr / gwangsangu / bukgu / seogu.gjtennis.kr

import { assert, assertEquals } from 'std/assert/mod.ts';
import { fetchDetail, parseListing } from '../_shared/crawler/parsers/gnuboard_sub5_5_contest.ts';
import type { DivisionDictRow } from '../_shared/crawler/divisions.ts';

const DICT: DivisionDictRow[] = [
  { code: 'gj_m_gold', synonyms: ['골드부', '골드'], label_ko: '골드부' },
  { code: 'gj_m_general', synonyms: ['남자일반부', '일반부', '남자일반'], label_ko: '일반부' },
  { code: 'gj_m_rookie', synonyms: ['남자신인부', '신인부', '신인'], label_ko: '신인부' },
  {
    code: 'gj_m_beginner',
    synonyms: ['비입상자부', '초급자', '초급자부', '테린이(남)'],
    label_ko: '초급자부',
  },
  { code: 'gj_w_beginner', synonyms: ['여자초급자부', '테린이(여)'], label_ko: '여자초급자부' },
  { code: 'kstf_60', synonyms: ['60대', '60부', '어르신60+'], label_ko: '60+부' },
  { code: 'kstf_65', synonyms: ['65대', '65부', '어르신65+'], label_ko: '65+부' },
  { code: 'kstf_70', synonyms: ['70대', '70부', '어르신70+'], label_ko: '70+부' },
];

function withFetch(html: string, fn: () => Promise<void>): Promise<void> {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(html, { status: 200 }))) as typeof fetch;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

// ── listing ───────────────────────────────────────────────────────────────
// 구 협회 목록에는 대회 게시판(game) 말고 자유게시판·갤러리 링크가 함께 있다.
const GU_LISTING = `
<html><body>
  <a href="/bbs/board.php?bo_table=game&wr_id=19">2026 광주오픈 국제 챌린저 초급자 테니스대회</a>
  <a href="/bbs/board.php?bo_table=game&wr_id=18">제9회 광주광역시 협회장배</a>
  <a href="/bbs/board.php?bo_table=free&wr_id=91">자유게시판 잡담</a>
  <a href="/bbs/board.php?bo_table=gallery&wr_id=7">갤러리 사진</a>
  <a href="/bbs/board.php?bo_table=game&wr_id=19#comment">같은 글 재등장(댓글 앵커)</a>
  <a href="/bbs/write.php?bo_table=game">글쓰기</a>
</body></html>
`;

Deno.test('parseListing: bo_table 이 있으면 같은 게시판의 wr_id 만 모은다', () => {
  const items = parseListing(
    GU_LISTING,
    'http://coach.gjtennis.kr/bbs/board.php?bo_table=game',
  );
  assertEquals(items.map((i) => i.sid), ['19', '18']);
  assert(
    items.every((i) => i.url.includes('bo_table=game')),
    '다른 게시판 링크가 섞였다',
  );
});

const LEGACY_LISTING = `
<html><body>
  <a href="/sub5_2_2_view.php?sid=108">2026 빛고을배 전국대회</a>
  <a href="/sub5_2_2_view.php?sid=107">제22회 광주광역시장배</a>
  <a href="/bbs/board.php?bo_table=free&wr_id=3">자유게시판</a>
</body></html>
`;

Deno.test('parseListing: bo_table 이 없으면 기존 sid 방식 그대로다(회귀)', () => {
  const items = parseListing(LEGACY_LISTING, 'https://gjtennis.kr/sub5_2_2.php');
  assertEquals(items.map((i) => i.sid), ['108', '107']);
});

// ── detail: 표준 그누보드 ─────────────────────────────────────────────────
// 요강 표(표2)가 신청현황표(표1) 뒤에 온다. 예전에는 컬럼 인덱스를 문서 전체 th
// 순번으로 잡아 이런 페이지에서 엉뚱한 칸을 날짜로 읽었다.
const SEOGU_DETAIL = `
<html><head><title>2026 어르신 건강 체육대회 (테니스대회) &gt; 대회신청 | 광주광역시 서구테니스협회</title></head>
<body>
  <h3>대회관련</h3>
  <div id="bo_v_con">
    <table>
      <tr><th>참가 부서</th><th>구분</th><th>신청기간</th><th>경기일시</th><th>현재신청팀</th></tr>
      <tr><td>남자부(개인)_어르신60+</td><td>단식</td><td>20260602 ~ 20260610 [마감]</td><td>20260614 09:00:00시</td><td>4 / 64</td></tr>
      <tr><td>남자부(개인)_어르신65+</td><td>단식</td><td>20260602 ~ 20260610 [마감]</td><td>20260614 09:00:00시</td><td>12 / 64</td></tr>
      <tr><td>남자부(개인)_어르신70+</td><td>단식</td><td>20260602 ~ 20260610 [마감]</td><td>20260614 09:00:00시</td><td>6 / 32</td></tr>
    </table>
    <table>
      <tr><th>신청기간</th><th>경기일시</th><th>비고</th></tr>
      <tr><td>2030년 1월 1일 ~ 2030년 2월 2일</td><td>2030년 3월 3일</td><td>작년 대회 안내(참고용)</td></tr>
      <tr><td>장 소</td><td>진월 국제테니스장</td><td>주최 광주광역시체육회</td></tr>
      <tr><td>골드부 우승자는 다음 대회부터 오픈부로 승급한다</td><td>승급 규칙 설명문</td><td>-</td></tr>
    </table>
  </div>
  <div class="footer">광주광역시테니스협회 진월국제테니스장 내</div>
</body></html>
`;

Deno.test('fetchDetail(구 협회): 제목·8자리 날짜·부서를 신청현황표에서 읽는다', async () => {
  await withFetch(SEOGU_DETAIL, async () => {
    const r = await fetchDetail(
      'http://seogu.gjtennis.kr/bbs/board.php?bo_table=game&wr_id=10',
      '광주',
      '',
      DICT,
    );
    const t = r?.tournament;
    assert(t, '파싱 실패');
    // h3 가 게시판 이름('대회관련')이라 <title> 을 쓴다.
    assertEquals(t!.title, '2026 어르신 건강 체육대회 (테니스대회)');
    // 구분자 없는 8자리 — 경기일은 첫 행, 마감은 신청기간의 마지막 날짜.
    assertEquals(t!.start_date, '2026-06-14');
    assertEquals(t!.application_deadline, '2026-06-10');
    // 시니어는 org 를 가려도 사전에 실린다(loadDivisionDict 가 kstf 를 함께 싣는다).
    assertEquals(t!.eligible_grades, ['kstf_60', 'kstf_65', 'kstf_70']);
    // 두 번째 표(요강)의 '골드부' 는 개설 부서가 아니다 — 승급 규칙 설명문이다.
    assert(!t!.eligible_grades.includes('gj_m_gold'), '요강 설명문의 부서가 섞였다');
    // 그 표에도 '신청기간/경기일시' 헤더와 2030년 날짜가 있다. 컬럼 인덱스를 문서
    // 전역 th 순번으로 잡으면 이쪽을 읽어 2030-03-03 이 나온다(옛 버그).
  });
});

// 지도자회: 남/여 초급자가 한 표에 있다. '테린이' 로만 매칭하면 여자 대회가
// 남자 부서로 잡히므로 성별 표기까지 포함한 synonym 을 쓴다.
const COACH_DETAIL = `
<html><head><title>2026 광주오픈 국제 챌린저 초급자 테니스대회 &gt; 대회신청 | 광주광역시테니스협회</title></head>
<body>
  <h3>대회관련</h3>
  <div id="bo_v_con">
    <table>
      <tr><td>부서</td><td>경기종류</td><td>테니스 기간</td><td>신청기간</td><td>경기일시</td></tr>
      <tr><td>테린이(남)</td><td>단식</td><td>1년미만</td><td>20260417 ~ 20260423 마감</td><td>20260426 09:00:00시</td></tr>
      <tr><td>테린이(여)</td><td>단식</td><td>1년미만</td><td>20260417 ~ 20260423 마감</td><td>20260426 09:00:00시</td></tr>
    </table>
  </div>
</body></html>
`;

Deno.test('fetchDetail(지도자회): 테린이 남/여가 각자 부서로 갈린다', async () => {
  await withFetch(COACH_DETAIL, async () => {
    const r = await fetchDetail(
      'http://coach.gjtennis.kr/bbs/board.php?bo_table=game&wr_id=19',
      '광주',
      '',
      DICT,
    );
    const t = r?.tournament;
    assert(t, '파싱 실패');
    assertEquals(t!.eligible_grades, ['gj_m_beginner', 'gj_w_beginner']);
    assertEquals(t!.start_date, '2026-04-26');
    assertEquals(t!.application_deadline, '2026-04-23');
  });
});

// 원본이 마감을 경기일 뒤로 적어둔 실제 케이스(광산구·서구 2025년 대회).
const LATE_DEADLINE_DETAIL = `
<html><head><title>2025년 광산구협회장기 &gt; 대회신청 | 광산구테니스협회</title></head>
<body>
  <h3>대회관련</h3>
  <div id="bo_v_con">
    <table>
      <tr><th>참가 부서</th><th>구분</th><th>신청기간</th><th>경기일시</th></tr>
      <tr><td>골드부</td><td>복식</td><td>20251018 ~ 20251205 [마감]</td><td>20251105 09:00:00시</td></tr>
    </table>
  </div>
</body></html>
`;

Deno.test('fetchDetail: 마감일이 경기일보다 늦으면 비운다(지어내지 않는다)', async () => {
  await withFetch(LATE_DEADLINE_DETAIL, async () => {
    const r = await fetchDetail(
      'http://gwangsangu.gjtennis.kr/bbs/board.php?bo_table=game&wr_id=1',
      '광주',
      '',
      DICT,
    );
    const t = r?.tournament;
    assert(t, '파싱 실패');
    assertEquals(t!.start_date, '2025-11-05');
    assertEquals(
      t!.application_deadline,
      undefined,
      '경기일보다 늦은 마감을 그대로 실으면 끝난 대회가 "마감 임박"으로 뜬다',
    );
  });
});

// ── detail: 커스텀 템플릿 회귀 ────────────────────────────────────────────
// <title> 이 사이트명이라, 길이만 비교해 채택하면 실제 대회 제목을 덮어쓴다.
const LEGACY_DETAIL = `
<html><head><title>광주광역시테니스협회 광주테니스협회 생활체육부</title></head>
<body>
  <div class="docContWrap">
    <h3>제3회 송도건설배 테니스대회</h3>
    <table>
      <tr><th>참가부서</th><th>신청기간</th><th>경기일시</th></tr>
      <tr><td>남자일반부</td><td>2026년 9월 22일 ~ 2026년 10월 21일 19시 까지</td><td>2026년 10월 24일</td></tr>
    </table>
  </div>
</body></html>
`;

Deno.test('fetchDetail(시협회): <title> 이 사이트명이어도 h3 제목을 지킨다(회귀)', async () => {
  await withFetch(LEGACY_DETAIL, async () => {
    const r = await fetchDetail('https://gjtennis.kr/sub5_2_2_view.php?sid=107', '광주', '', DICT);
    const t = r?.tournament;
    assert(t, '파싱 실패');
    // h3(16자)가 <title>(24자)보다 **짧다** — 길이만 비교하면 협회명으로 덮인다.
    assertEquals(t!.title, '제3회 송도건설배 테니스대회');
    assertEquals(t!.start_date, '2026-10-24');
    assertEquals(t!.application_deadline, '2026-10-21');
    assertEquals(t!.eligible_grades, ['gj_m_general']);
  });
});
