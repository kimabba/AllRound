// crawler_extract_test.ts
// _shared/crawler.ts 의 extractDate / extractApplicationDeadline 단위 테스트.
//
// 회귀 방지 목적:
//   - 한국 협회 사이트의 본문이 한국어 형식 "YYYY년 M월 D일" 를 주로 쓰는데
//     기존 숫자 전용 정규식은 매치하지 못해, 은행 계좌번호 등에서 false-positive
//     날짜가 추출되는 버그가 있었다 (예: "784902-01-022035" → "4902-01-02").
//   - 본 테스트는 한국어 매칭 우선 + 연도 sanity 검증 동작을 고정한다.

import { assert, assertEquals } from 'std/assert/mod.ts';
import { DOMParser } from 'deno-dom';
import {
  extractApplicationDeadline,
  extractDate,
  extractRegulationBody,
  extractRegulationFields,
  extractRegulationNotes,
  extractVenue,
} from '../_shared/crawler.ts';

Deno.test('extractDate parses Korean format first', () => {
  const text = '경기일시 : 2026년 4월 5일(일) 09시~ ...';
  assertEquals(extractDate(text), '2026-04-05');
});

Deno.test('extractDate parses numeric YYYY-MM-DD as fallback', () => {
  const text = '게시일 2026-03-16 14:25:54';
  assertEquals(extractDate(text), '2026-03-16');
});

Deno.test('extractDate rejects out-of-range year (sanity guard)', () => {
  // 은행 계좌번호 "784902-01-022035" → "4902-01-02" false positive.
  // 현재 연도 + 5 초과 → null 반환.
  const text = '입금계좌 : (국민은행 784902-01-022035, 예금주 : 신용관)';
  assertEquals(extractDate(text), null);
});

Deno.test('extractDate prefers in-range Korean date over out-of-range numeric', () => {
  // 한국어 형식 매칭이 먼저 후보로 들어가므로, sanity 통과한 첫 매치를 반환.
  const text = '계좌 784902-01-022035 / 경기일 2026년 5월 10일';
  assertEquals(extractDate(text), '2026-05-10');
});

Deno.test('extractDate rejects nonsense month/day even if year ok', () => {
  // 2026-13-45 는 month/day 범위 밖 → 다음 매치 시도, 없으면 null.
  assertEquals(extractDate('2026-13-45'), null);
});

Deno.test('extractDate returns null on empty / no date', () => {
  assertEquals(extractDate(''), null);
  assertEquals(extractDate('no dates here'), null);
});

Deno.test('extractApplicationDeadline parses Korean format with label', () => {
  const text = '신청기간 : 2026년 3월 16일 ~ 2026년 4월 1일 18시까지';
  const r = extractApplicationDeadline(text);
  // 라벨 직후 첫 매치 → 시작 일자가 들어옴 (기존 동작 보존).
  assertEquals(r, '2026-03-16');
});

Deno.test('extractApplicationDeadline parses numeric with label', () => {
  const text = '접수마감 2026-04-01 까지';
  assertEquals(extractApplicationDeadline(text), '2026-04-01');
});

Deno.test('extractApplicationDeadline parses 까지 with Korean date (no label)', () => {
  const text = '2026년 4월 1일까지 접수합니다.';
  assertEquals(extractApplicationDeadline(text), '2026-04-01');
});

Deno.test('extractApplicationDeadline rejects out-of-range year', () => {
  // 은행 계좌번호 형태가 들어와도 마감일로 채택되지 않아야 함.
  const text = '계좌 784902-01-022035 까지';
  // 라벨 없음 + sanity 실패 → null
  const r = extractApplicationDeadline(text);
  assert(r === null, `expected null, got ${r}`);
});

Deno.test('extractVenue extracts facility name from body (no label)', () => {
  const text = '단체전 예선 배정팀 중 진월국제테니스장은 8시30분 경기시작';
  assertEquals(extractVenue(text), '진월국제테니스장');
});

Deno.test('extractVenue prefers labeled location', () => {
  const text = '일시 2026년 3월 7일 경기장 광주시민테니스장 에서 진행';
  assertEquals(extractVenue(text), '광주시민테니스장');
});

Deno.test('extractVenue returns null when no facility name', () => {
  assertEquals(extractVenue('참가비 입금 안내 function accounting_price_ser()'), null);
});

// =============================================================================
// 대회 요강 정형화 — extractRegulationFields / extractRegulationNotes
//
// 협회 공고 원본은 MS-Word 내보내기 <table> 구조다. 라벨셀 + 값셀 행을 직접
// 구조화해 regulation_fields 로, ※ 안내문을 regulation_notes 로 추출한다.
// 큰 원본 HTML 은 커밋하지 않고, 라벨표 몇 행 + ※ 안내문을 담은 작은 인라인
// fixture 로 동작을 고정한다.
// =============================================================================

// 실제 원본 구조 모사: 라벨 내부 공백("장 소"), colspan 값셀,
// 화이트리스트 밖 라벨("입금계좌"), 빈 값 셀, ※ 안내문 포함.
const REGULATION_FIXTURE = `
<html><body>
<table>
  <tr>
    <td><p><span>장 소</span></p></td>
    <td colspan="2"><p><span>영암종합스포츠타운테니스장 외 보조경기장</span></p></td>
  </tr>
  <tr>
    <td><p><span>주 최</span></p></td>
    <td colspan="2"><p><span>영암군 체육회</span></p></td>
  </tr>
  <tr>
    <td><p><span>사 용 구</span></p></td>
    <td colspan="2"><p><span>헤드 챔피언십 테니스 볼 (생활체육 공식사용구)</span></p></td>
  </tr>
  <tr>
    <td><p><span>입금계좌</span></p></td>
    <td colspan="2"><p><span>국민은행 784902-01-022035</span></p></td>
  </tr>
  <tr>
    <td><p><span>협 찬</span></p></td>
    <td colspan="2"><p><span></span></p></td>
  </tr>
</table>
<p>※ 참가비로 스포츠공제보험에 가입합니다.</p>
<p>※ 우천 시 일정이 변경될 수 있습니다.</p>
</body></html>
`;

function parseFixture(html: string) {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('fixture parse failed');
  return dom;
}

Deno.test('extractRegulationFields returns whitelisted label:value in table order', () => {
  const dom = parseFixture(REGULATION_FIXTURE);
  const fields = extractRegulationFields(dom);
  assertEquals(fields, [
    { label: '장소', value: '영암종합스포츠타운테니스장 외 보조경기장' },
    { label: '주최', value: '영암군 체육회' },
    { label: '사용구', value: '헤드 챔피언십 테니스 볼 (생활체육 공식사용구)' },
  ]);
});

Deno.test('extractRegulationFields normalizes label inner whitespace ("장 소" → "장소")', () => {
  const dom = parseFixture(REGULATION_FIXTURE);
  const fields = extractRegulationFields(dom);
  assert(fields.some((f) => f.label === '장소'), 'expected normalized 장소 label');
  // 공백 섞인 원본 라벨이 그대로 남지 않아야 함
  assert(!fields.some((f) => f.label.includes(' ')), 'label must not contain spaces');
});

Deno.test('extractRegulationFields excludes non-whitelisted labels (입금계좌)', () => {
  const dom = parseFixture(REGULATION_FIXTURE);
  const fields = extractRegulationFields(dom);
  assert(!fields.some((f) => f.label === '입금계좌'), '입금계좌 must be excluded');
});

Deno.test('extractRegulationFields skips empty value cell (협찬)', () => {
  const dom = parseFixture(REGULATION_FIXTURE);
  const fields = extractRegulationFields(dom);
  // 협 찬 은 화이트리스트지만 값이 비어 있어 제외돼야 함
  assert(!fields.some((f) => f.label === '협찬'), 'empty-value 협찬 must be skipped');
});

Deno.test('extractRegulationFields dedupes repeated label (first wins)', () => {
  const dom = parseFixture(`
    <table>
      <tr><td><span>주 최</span></td><td><span>첫번째 주최</span></td></tr>
      <tr><td><span>주 최</span></td><td><span>두번째 주최</span></td></tr>
    </table>
  `);
  const fields = extractRegulationFields(dom);
  assertEquals(fields, [{ label: '주최', value: '첫번째 주최' }]);
});

// 실원본 모사: 각 ※ 안내문이 독립 <p> 요소. 표 행과 ※ <p> 가 섞여 있어도
// <p> 경계 기준 추출이라 표 텍스트("장 소"/"영암장")가 노트에 섞이면 안 된다.
const NOTES_FIXTURE = `
<html><body>
<table>
  <tr><td><p>※ 우천 시 일정은 추후 안내</p></td></tr>
  <tr><td><p>장 소</p></td><td><p>영암장</p></td></tr>
  <tr><td><p>주 최</p></td><td><p>영암군 체육회</p></td></tr>
</table>
<p>※ 참가비로 스포츠공제보험에 가입합니다.</p>
<p>일반 안내 문장 (※ 아님)</p>
<p>※ 참가비로 스포츠공제보험에 가입합니다.</p>
</body></html>
`;

Deno.test('extractRegulationNotes extracts per <p>, no table contamination', () => {
  const dom = parseFixture(NOTES_FIXTURE);
  const notes = extractRegulationNotes(dom);
  // ※ 마커 제거 + dedupe(같은 문장 2회 → 1회).
  assertEquals(notes, [
    '우천 시 일정은 추후 안내',
    '참가비로 스포츠공제보험에 가입합니다.',
  ]);
  // 표 값이 어느 노트에도 섞이지 않아야 함 (run-on 오염 방지 핵심).
  for (const note of notes) {
    assert(!note.includes('장 소'), `note leaked table label: ${note}`);
    assert(!note.includes('영암장'), `note leaked table value: ${note}`);
    assert(!note.includes('주 최'), `note leaked table label: ${note}`);
  }
});

Deno.test('extractRegulationNotes returns [] when no ※ paragraph', () => {
  const dom = parseFixture(
    '<html><body><p>마커 없는 안내</p><table><tr><td>장 소</td><td>영암장</td></tr></table></body></html>',
  );
  assertEquals(extractRegulationNotes(dom), []);
});

Deno.test('extractRegulationNotes splits multiple ※ within one <p>', () => {
  const dom = parseFixture('<html><body><p>※ 첫 안내 ※ 둘째 안내</p></body></html>');
  assertEquals(extractRegulationNotes(dom), ['첫 안내', '둘째 안내']);
});

Deno.test('extractRegulationNotes filters overly long fragments (>300 chars)', () => {
  const long = 'x'.repeat(350);
  const dom = parseFixture(`<html><body><p>※ 짧은 안내</p><p>※ ${long}</p></body></html>`);
  assertEquals(extractRegulationNotes(dom), ['짧은 안내']);
});

Deno.test('extractRegulationNotes drops short section-title headers (사항/규정), keeps real notes', () => {
  const dom = parseFixture(
    '<html><body>' +
      '<p>※ 제한사항</p>' +
      '<p>※ 대회운영에 관한 사항</p>' +
      '<p>※ 랭킹규정에 관한 사항</p>' +
      '<p>※ 90팀 미만 상금 조정함.</p>' +
      '<p>※ 우천 시 대회운영 시간 및 게임방식은 변경 될 수 있거나 대회 일정 추후 안내</p>' +
      '<p>※ 대회운영에 관한 사항 사무장 최임수 010-3620-7479 총무이사 김정은 010-8239-6050</p>' +
      '</body></html>',
  );
  // 짧은 명사구 헤더 3개는 제외, 어미 다른 짧은 노트·긴 노트·본문 포함 헤더는 보존.
  assertEquals(extractRegulationNotes(dom), [
    '90팀 미만 상금 조정함.',
    '우천 시 대회운영 시간 및 게임방식은 변경 될 수 있거나 대회 일정 추후 안내',
    '대회운영에 관한 사항 사무장 최임수 010-3620-7479 총무이사 김정은 010-8239-6050',
  ]);
});

Deno.test('extractRegulationNotes falls back to text split when no <p> notes', () => {
  // <p> 가 없고 노트가 div 등 평문 안에 있는 비-테이블 source 폴백.
  // doc.querySelectorAll('p') 가 비므로 doc 전체 textContent 평문 split 로 폴백.
  const dom = parseFixture(
    '<html><body><div>대회 안내 ※ 보험 가입함 ※ 우천 시 변경</div></body></html>',
  );
  assertEquals(extractRegulationNotes(dom), ['보험 가입함', '우천 시 변경']);
});

// =============================================================================
// 대회 요강 완전 본문 — extractRegulationBody
//
// 콘텐츠표(화이트리스트 라벨 다수)를 행 구조를 살려 직렬화하되 fields/notes/배너/
// 빈행을 제외한다. 신청현황표(참가부서/신청기간/63·192)는 표 단위로 제외.
// =============================================================================

// 실원본 모사: 신청현황표(TABLE 0) + 콘텐츠표(TABLE 1).
const BODY_FIXTURE = `
<html><body>
<table>
  <tr><td>참가부서</td><td>신청기간</td><td>경기일시</td><td>현재신청팀</td><td>신청하기</td><td>입금내역</td></tr>
  <tr><td>남자일반부</td><td>2026년 6월 23일 ~ 7월 1일 [신청중]</td><td>2026년 7월 4일</td><td>63 / 192</td><td></td><td></td></tr>
</table>
<table>
  <tr><td>『Sports 7330』 일주일에 3번</td></tr>
  <tr><td>제5회 영암월출산배 전남 생활체육 테니스대회</td></tr>
  <tr><td>풋 폴트를 하지 맙시다</td></tr>
  <tr><td>일 시</td><td>2026년 7월 4일(토) / 남자일반부(09:00)</td></tr>
  <tr><td>※ 우천 시 일정 추후 안내</td></tr>
  <tr><td>장 소</td><td>영암종합스포츠타운테니스장</td></tr>
  <tr><td>주 최</td><td>영암군 체육회</td></tr>
  <tr><td>경기종목</td><td>경기일자</td><td>참가비 입금계좌</td></tr>
  <tr><td>남자일반부(192팀)</td><td>7월 4일(토) 09시00분</td><td>입금계좌 : 농협 667-02-238327</td></tr>
  <tr><td></td><td></td><td></td></tr>
  <tr><td>참가신청 및접수마감</td><td>◈ 2026년 7월 1일 18:00까지</td></tr>
  <tr><td>◈ 남자일반부</td></tr>
  <tr><td>- 우 승 : 시상금 110만원</td></tr>
</table>
</body></html>
`;

Deno.test('extractRegulationBody serializes content table with row structure', () => {
  const dom = parseFixture(BODY_FIXTURE);
  const body = extractRegulationBody(dom, '제5회 영암월출산배 전남 생활체육 테니스대회');
  assert(body !== null, 'body should not be null');
  const lines = body!.split('\n');
  // 2칸 → "라벨: 값" (라벨 내부 공백 정규화 "일 시" → "일시")
  assert(
    lines.includes('일시: 2026년 7월 4일(토) / 남자일반부(09:00)'),
    `missing 일시 line: ${body}`,
  );
  // 3칸 → "셀1 | 셀2 | 셀3"
  assert(
    lines.includes('남자일반부(192팀) | 7월 4일(토) 09시00분 | 입금계좌 : 농협 667-02-238327'),
    `missing 3-col line: ${body}`,
  );
  // 1칸 → 텍스트 그대로 (◈ 줄)
  assert(lines.includes('◈ 남자일반부'), `missing 1-col ◈ line: ${body}`);
  assert(lines.includes('- 우 승 : 시상금 110만원'), `missing 시상 detail: ${body}`);
  // 비-화이트리스트 라벨 행은 "라벨: 값" 으로 보존 (접수마감)
  assert(
    lines.includes('참가신청및접수마감: ◈ 2026년 7월 1일 18:00까지'),
    `missing 접수마감 line: ${body}`,
  );
});

Deno.test('extractRegulationBody excludes fields, notes, banners, empty, application table', () => {
  const dom = parseFixture(BODY_FIXTURE);
  const body = extractRegulationBody(dom, '제5회 영암월출산배 전남 생활체육 테니스대회')!;
  // (a) 화이트리스트 라벨 행 제외 (fields 와 중복 방지)
  assert(!body.includes('장 소') && !body.includes('장소:'), `장소 leaked: ${body}`);
  assert(!body.includes('주 최') && !body.includes('주최:'), `주최 leaked: ${body}`);
  // (b) ※ 노트 행 제외
  assert(!body.includes('※ 우천'), `※ note leaked: ${body}`);
  // (c) 배너 행 제외 (『』, Sports 7330, 풋 폴트, title)
  assert(!body.includes('Sports 7330'), `banner leaked: ${body}`);
  assert(!body.includes('풋 폴트'), `풋 폴트 banner leaked: ${body}`);
  assert(!body.includes('영암월출산배'), `title banner leaked: ${body}`);
  // 신청현황표(TABLE 0) 전체 제외 — 라이브 카운트/헤더 없어야 함
  assert(!body.includes('63 / 192'), `application count leaked: ${body}`);
  assert(!body.includes('참가부서'), `application header leaked: ${body}`);
  assert(!body.includes('신청기간'), `application header leaked: ${body}`);
});

Deno.test('extractRegulationBody returns null when no content table', () => {
  // 화이트리스트 라벨이 없는 표뿐이면 콘텐츠표 후보 없음 → null.
  const dom = parseFixture(
    '<html><body><table><tr><td>아무 텍스트</td></tr></table></body></html>',
  );
  assertEquals(extractRegulationBody(dom), null);
});
