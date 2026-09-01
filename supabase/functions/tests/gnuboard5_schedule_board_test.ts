// gnuboard5_schedule_board_test.ts
// 전북(jbsta.com) 표준 그누보드5 대회일정 parser 순수 함수 단위 테스트 (네트워크 없음).
//
// 픽스처 2종:
//   - fixtures/jb_schedule_*.html — 2026-08-26 jbsta.com 실측 원본(리스트 뷰·상세 wr_id=1172)
//   - 인라인 HTML — 엣지 케이스(공지 상단고정 이중출현, 페이지네이션 파라미터,
//     빈 텍스트 앵커, 연말 경계 연도추론 등)
//
// now 는 항상 고정값을 주입해 결정성을 확보한다(inferYear 규약).

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildTournament,
  extractMonthDays,
  inferYear,
  parseScheduleDetail,
  parseScheduleListing,
  resolveAnchorYear,
  type ScheduleDetail,
} from '../_shared/crawler/parsers/gnuboard5_schedule_board.ts';
import type { DivisionDictRow } from '../_shared/crawler/divisions.ts';

const BASE = 'https://www.jbsta.com/bbs/board.php?bo_table=schedule&gubun=list';
// 실측 픽스처(2026-08-26 크롤)와 시간적으로 정합한 고정 now.
const NOW = new Date('2026-08-26T03:00:00Z');

async function fixture(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(`./fixtures/${name}`, import.meta.url));
}

// jb 부서 사전 — 정본 KB JSON 에서 로드해 seed/파서와 같은 데이터로 검증한다.
async function jbDict(): Promise<DivisionDictRow[]> {
  const kb = JSON.parse(
    await Deno.readTextFile(new URL('../../../docs/kb/grades/jb.divisions.json', import.meta.url)),
  ) as { divisions: Array<{ code: string; synonyms: string[]; label_ko: string }> };
  return kb.divisions.map((d) => ({
    code: d.code,
    synonyms: d.synonyms,
    label_ko: d.label_ko,
  }));
}

// =============================================================================
// 목록 파싱
// =============================================================================
Deno.test('parseScheduleListing: 실측 리스트 뷰 — wr_id 전건 추출 + canonical URL', async () => {
  const items = parseScheduleListing(await fixture('jb_schedule_list.html'), BASE);
  assert(items.length >= 40, `기대(>=40)보다 적음: ${items.length}`);

  // wr_id 중복 없음
  const ids = items.map((it) => it.wrId);
  assertEquals(new Set(ids).size, ids.length);

  const buan = items.find((it) => it.wrId === '1172');
  assert(buan, 'wr_id=1172(부안마실배) 미추출');
  assertEquals(buan.url, 'https://www.jbsta.com/bbs/board.php?bo_table=schedule&wr_id=1172');
  assert(buan.title.includes('부안마실배'));

  // 모든 URL 이 canonical 형태(bo_table+wr_id 만)여야 중복 insert 가 없다.
  for (const it of items) {
    assertEquals(it.url, `https://www.jbsta.com/bbs/board.php?bo_table=schedule&wr_id=${it.wrId}`);
  }
});

const EDGE_LISTING = `
<table>
  <!-- 공지 상단고정: 같은 글이 목록에 두 번 -->
  <tr><td><a href="/bbs/board.php?bo_table=schedule&wr_id=100">공지 대회 A</a></td></tr>
  <tr><td><a href="/bbs/board.php?bo_table=schedule&wr_id=101&page=2&sfl=wr_subject&stx=%EB%8C%80%ED%9A%8C">대회 B</a></td></tr>
  <tr><td><a href="/bbs/board.php?bo_table=schedule&wr_id=100&page=1">공지 대회 A</a></td></tr>
  <!-- 빈 텍스트(이미지) 앵커 -->
  <tr><td><a href="/bbs/board.php?bo_table=schedule&wr_id=102"><img src="/p.png"></a></td></tr>
  <!-- 다른 게시판 -->
  <tr><td><a href="/bbs/board.php?bo_table=ranking&wr_id=103">랭킹 글</a></td></tr>
  <!-- wr_id 없는 링크(페이지네이션) -->
  <tr><td><a href="/bbs/board.php?bo_table=schedule&gubun=list&page=2">2</a></td></tr>
</table>`;

Deno.test('parseScheduleListing: 공지 이중출현 dedupe + 파라미터 제거 + 빈 앵커/타 게시판 skip', () => {
  const items = parseScheduleListing(EDGE_LISTING, BASE);
  assertEquals(items.map((it) => it.wrId), ['100', '101']);
  // 페이지네이션·검색 파라미터가 제거된 canonical URL
  assertEquals(
    items[1].url,
    'https://www.jbsta.com/bbs/board.php?bo_table=schedule&wr_id=101',
  );
});

// =============================================================================
// extractMonthDays / resolveAnchorYear / inferYear
// =============================================================================
Deno.test('extractMonthDays: 연도 없는 M월D일 전수 매치', () => {
  assertEquals(extractMonthDays('04월03일 ~ 04월19일[신청마감]'), [
    { month: 4, day: 3 },
    { month: 4, day: 19 },
  ]);
  assertEquals(extractMonthDays('04월25일09시분'), [{ month: 4, day: 25 }]);
  assertEquals(extractMonthDays('4월 5일'), [{ month: 4, day: 5 }]);
  assertEquals(extractMonthDays('13월40일 접수'), []); // 범위 밖은 버린다
  assertEquals(extractMonthDays('추후 공지'), []);
});

Deno.test('resolveAnchorYear: 제목 연도 → 작성일 → 크롤시점 폴백', () => {
  assertEquals(resolveAnchorYear('2026년 제8회 부안마실배', '', '', NOW), {
    year: 2026,
    source: 'text',
  });
  // 제목에 연도 없음 → 그누보드 작성일(YY-MM-DD)
  assertEquals(resolveAnchorYear('제54회 도지사배', '', '작성일 25-12-03 16:19', NOW), {
    year: 2025,
    source: 'written',
  });
  // 아무것도 없음 → 크롤시점 KST 연도
  assertEquals(resolveAnchorYear('도지사배', '', '', NOW), { year: 2026, source: 'crawl' });
});

Deno.test('inferYear: 같은 해 시간축 — 앵커연도 그대로', () => {
  const timeline = [{ month: 4, day: 3 }, { month: 4, day: 19 }, { month: 4, day: 25 }];
  assertEquals(
    inferYear(timeline, 2, { year: 2026, source: 'text' }, NOW),
    ['2026-04-03', '2026-04-19', '2026-04-25'],
  );
});

Deno.test('inferYear: 연말 경계 — 12월 접수 → 1월 경기는 +1년', () => {
  const now = new Date('2025-12-05T03:00:00Z');
  const timeline = [{ month: 12, day: 20 }, { month: 12, day: 28 }, { month: 1, day: 5 }];
  assertEquals(
    inferYear(timeline, 2, { year: 2025, source: 'text' }, now),
    ['2025-12-20', '2025-12-28', '2026-01-05'],
  );
});

Deno.test('inferYear: 크롤시점 보정 — 앵커가 크롤 폴백이고 경기일이 60일+ 과거면 +1년', () => {
  const now = new Date('2026-12-30T03:00:00Z');
  assertEquals(
    inferYear([{ month: 1, day: 10 }], 0, { year: 2026, source: 'crawl' }, now),
    ['2027-01-10'],
  );
  // 앵커가 명시적(text/written)이면 과거여도 보정하지 않는다.
  assertEquals(
    inferYear([{ month: 1, day: 10 }], 0, { year: 2026, source: 'written' }, now),
    ['2026-01-10'],
  );
});

Deno.test('inferYear: sanity — 경기일이 −12~+18개월 밖이면 추론실패(null)', () => {
  // 2024년 대회를 2026-08 에 보면 −12개월 밖 → null (지어내지 않는다)
  assertEquals(inferYear([{ month: 5, day: 1 }], 0, { year: 2024, source: 'text' }, NOW), null);
  // +18개월 밖(2028-05)도 null
  assertEquals(inferYear([{ month: 5, day: 1 }], 0, { year: 2028, source: 'text' }, NOW), null);
  // 달력에 없는 날짜(2월 30일)도 null
  assertEquals(inferYear([{ month: 2, day: 30 }], 0, { year: 2026, source: 'text' }, NOW), null);
});

// =============================================================================
// 상세 파싱 — 실측 픽스처 (wr_id=1172, 2026 부안마실배)
// =============================================================================
Deno.test('parseScheduleDetail: 실측 상세 — 제목/경기일/마감/부서/포스터', async () => {
  const detail = parseScheduleDetail(
    await fixture('jb_schedule_detail_1172.html'),
    '2026년 『제8회 부안마실배』전북특별자치도 동호인테니스대회',
    NOW,
  ) as ScheduleDetail;
  assert(detail !== null, '파싱 실패');

  assert(detail.title.includes('부안마실배'));
  // 남자동배부 04월25일 / 남자금은배부 04월26일 → min=start, max=end
  assertEquals(detail.startDate, '2026-04-25');
  assertEquals(detail.endDate, '2026-04-26');
  // 신청기간 04월03일~04월19일 / 04월03일~04월22일 → 마지막 날짜 max
  assertEquals(detail.deadline, '2026-04-22');
  assert(detail.divisionText.includes('남자동배부'));
  assert(detail.divisionText.includes('남자금은배부'));
  assert(detail.posterUrl?.includes('/data/editor/'), `poster: ${detail.posterUrl}`);
});

// 경기일+신청기간 th 를 모두 가진 표가 없으면(요강표만 있으면) 가드 실패 → null.
Deno.test('parseScheduleDetail: 신청현황표 없는 게시물(선거 공지 등)은 null', () => {
  const html = `
    <h1 id="bo_v_title">제27대 협회장 선거</h1>
    <section id="bo_v_atc">
      <table><tr><th>구분</th><th>경기일시</th></tr><tr><td>후보등록</td><td>01월10일</td></tr></table>
    </section>`;
  assertEquals(parseScheduleDetail(html, '제27대 협회장 선거', NOW), null);
});

// 마감이 경기일보다 늦으면(원문 오류) 값을 지어내지 않고 비운다.
Deno.test('parseScheduleDetail: 마감 > 경기일이면 deadline 비움', () => {
  const html = `
    <h1 id="bo_v_title">2026년 테스트 대회</h1>
    <section id="bo_v_atc">
      <table class="take_part">
        <tr><th>참 가 부 서</th><th>신 청 기 간</th><th>경 기 일 시</th></tr>
        <tr><td>남자동배부</td><td>04월03일 ~ 05월30일</td><td>04월25일09시분</td></tr>
      </table>
    </section>`;
  const detail = parseScheduleDetail(html, '', NOW) as ScheduleDetail;
  assertEquals(detail.startDate, '2026-04-25');
  assertEquals(detail.deadline, null);
});

// =============================================================================
// buildTournament — jb 부서 사전 매핑
// =============================================================================
Deno.test('buildTournament: 참가부서 셀 → jb_* 코드 매핑 + region/organizer 폴백', async () => {
  const dict = await jbDict();
  const detail = parseScheduleDetail(
    await fixture('jb_schedule_detail_1172.html'),
    '2026년 『제8회 부안마실배』전북특별자치도 동호인테니스대회',
    NOW,
  ) as ScheduleDetail;
  const t = buildTournament(
    {
      wrId: '1172',
      url: 'https://www.jbsta.com/bbs/board.php?bo_table=schedule&wr_id=1172',
      title: 'x',
    },
    detail,
    dict,
    '전북',
  );
  assertEquals(t.eligible_grades.toSorted(), ['jb_m_dong', 'jb_m_geumeun']);
  assert(t.division_label_local?.includes('남자동배부'));
  assertEquals(t.start_date, '2026-04-25');
  assertEquals(t.end_date, '2026-04-26');
  assertEquals(t.application_deadline, '2026-04-22');
  assertEquals(t.region, '전북');
  assertEquals(t.organizer, '전북테니스협회');
  assertEquals(t.source_url, 'https://www.jbsta.com/bbs/board.php?bo_table=schedule&wr_id=1172');
  assertEquals(t.entry_fee, undefined); // 텍스트에 없음 — 포스터 추출 파이프라인 몫
});

Deno.test('buildTournament: 합산대회·단체전·미매칭 케이스', async () => {
  const dict = await jbDict();
  const base: ScheduleDetail = {
    title: '2026년 만경강배',
    startDate: '2026-09-01',
    endDate: null,
    deadline: null,
    divisionText: '',
    posterUrl: null,
    bodyText: '',
  };
  const item = { wrId: '1', url: 'https://x/board.php?bo_table=schedule&wr_id=1', title: 'x' };

  const hapsan = buildTournament(
    { ...item },
    { ...base, divisionText: '남자합산10점대회 여자합산5점대회' },
    dict,
    '전북',
  );
  assertEquals(hapsan.eligible_grades.toSorted(), ['jb_m_hapsan', 'jb_w_hapsan']);

  const team = buildTournament(
    { ...item },
    { ...base, divisionText: '단체전(남자통합부) 단체전(여자통합부) 국화부' },
    dict,
    '전북',
  );
  assertEquals(team.eligible_grades.toSorted(), ['jb_gukhwa', 'jb_team']);

  // 미매칭이면 codes=[] — 기본값을 추측하지 않는다(draft 검수에서 보정).
  const unmapped = buildTournament(
    { ...item },
    { ...base, divisionText: '알수없는부' },
    dict,
    '전북',
  );
  assertEquals(unmapped.eligible_grades, []);
});
