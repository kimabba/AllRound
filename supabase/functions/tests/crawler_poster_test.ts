// crawler_poster_test.ts
// P6 포스터 URL 수집 — 공용 extractPosterUrl + gj/jn·KATO 파서 배선 테스트.
// 네트워크 없음: 순수 함수는 인라인 픽스처, fetchDetail 은 globalThis.fetch 스텁.

import { assert, assertEquals } from 'std/assert/mod.ts';
import { extractPosterUrl } from '../_shared/crawler/poster.ts';
import { fetchDetail } from '../_shared/crawler/parsers/gnuboard_sub5_5_contest.ts';
import {
  type KatoDetailFields,
  parseKatoDetail,
} from '../_shared/crawler/parsers/kato_openlist.ts';

const BASE = 'https://example.or.kr/view.php?sid=1';

Deno.test('extractPosterUrl: 첫 <img> src 를 절대경로로 뽑는다', () => {
  assertEquals(
    extractPosterUrl('<p><img src="/data/editor/poster1.jpg"><img src="/data/p2.jpg"></p>', BASE),
    'https://example.or.kr/data/editor/poster1.jpg',
  );
  assertEquals(extractPosterUrl('<p>이미지 없음</p>', BASE), null);
  assertEquals(extractPosterUrl(null, BASE), null);
  assertEquals(extractPosterUrl('', BASE), null);
});

Deno.test('extractPosterUrl: data URI·UI 이미지(로고/아이콘/버튼)는 건너뛴다', () => {
  const html = '<img src="data:image/png;base64,AAAA">' +
    '<img src="/images/top_logo.png">' +
    '<img src="/images/icon-cal.gif">' +
    '<img src="/common/btn_list.png">' +
    '<img src="/data/file/poster.jpg">';
  assertEquals(extractPosterUrl(html, BASE), 'https://example.or.kr/data/file/poster.jpg');
  // UI 이미지뿐이면 null — 로고를 포스터로 오인하지 않는다.
  assertEquals(extractPosterUrl('<img src="/images/top_logo.png">', BASE), null);
});

Deno.test('extractPosterUrl: 업로드 경로 이미지를 사이트 chrome 이미지보다 우선한다', () => {
  const html = '<img src="/assets/images/system/groupma_60.png">' +
    '<img src="/upload/editor/2026/poster.png">';
  assertEquals(extractPosterUrl(html, BASE), 'https://example.or.kr/upload/editor/2026/poster.png');
});

Deno.test('extractPosterUrl: 구분자 없는 단어(naver 등)는 UI 패턴으로 오인하지 않는다', () => {
  // 'naver' 안의 nav, 'renavigate' 등 부분 문자열 매치 방지.
  assertEquals(
    extractPosterUrl('<img src="/files/naver_poster.jpg">', BASE),
    'https://example.or.kr/files/naver_poster.jpg',
  );
});

Deno.test('extractPosterUrl: http(s) 이외 프로토콜·깨진 URL 은 무시한다', () => {
  const html = '<img src="javascript:alert(1)"><img src="/data/ok.jpg">';
  assertEquals(extractPosterUrl(html, BASE), 'https://example.or.kr/data/ok.jpg');
});

// =============================================================================
// KATO 상세 — parseKatoDetail 이 posterUrl 을 채운다
// =============================================================================

Deno.test('parseKatoDetail: 공고 내 업로드 이미지를 posterUrl 로 수집한다', () => {
  const html = `
<img src="/assets/logo_kato.png">
<div class="group-title">제1회 테스트배</div>
<table><tr><td>주 최</td><td>협회</td></tr></table>
<p><img src="/upload/2026/poster_final.jpg"></p>`;
  const d = parseKatoDetail(html, '힌트', 'https://kato.kr/openGame/0299') as KatoDetailFields;
  assertEquals(d.posterUrl, 'https://kato.kr/upload/2026/poster_final.jpg');
});

Deno.test('parseKatoDetail: 이미지 없는 공고는 posterUrl undefined (기존 필드 보존용)', () => {
  const d = parseKatoDetail(
    '<div class="group-title">제1회 테스트배</div><table><tr><td>주 최</td><td>협회</td></tr></table>',
    '힌트',
  ) as KatoDetailFields;
  assertEquals(d.posterUrl, undefined);
});

// =============================================================================
// gj/jn (gnuboard) 상세 — fetchDetail 이 본문 컨테이너의 포스터만 수집한다
// =============================================================================

const GNUBOARD_POSTER_FIXTURE = `
<html><body>
<div class="gnb"><img src="/images/site_logo.png"></div>
<h3>제10회 테스트배 테니스대회</h3>
<table>
  <tr><th>참가부서</th><th>신청기간</th><th>경기일시</th></tr>
  <tr><td>남자일반부</td><td>2026년 5월 1일 ~ 2026년 5월 15일 18시 까지</td><td>2026년 5월 30일</td></tr>
</table>
<p><img src="/data/editor/2026/tournament_poster.jpg"></p>
<div class="footer"><img src="/images/footer_banner.png"></div>
</body></html>
`;

Deno.test('gnuboard fetchDetail: 본문 이미지가 poster_url 로 수집된다 (노이즈 로고 제외)', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch =
    (() => Promise.resolve(new Response(GNUBOARD_POSTER_FIXTURE, { status: 200 }))) as typeof fetch;
  try {
    const result = await fetchDetail(
      'https://gjtennis.kr/sub5_2_2_view.php?sid=1',
      '광주',
      '힌트제목',
      [],
    );
    assert(result?.tournament, 'tournament should be parsed');
    assertEquals(
      result.tournament.poster_url,
      'https://gjtennis.kr/data/editor/2026/tournament_poster.jpg',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('gnuboard fetchDetail: 본문에 이미지가 없으면 poster_url 미방출(undefined) — 기존 값 보존', async () => {
  const noPoster = GNUBOARD_POSTER_FIXTURE.replace(
    '<p><img src="/data/editor/2026/tournament_poster.jpg"></p>',
    '',
  );
  const originalFetch = globalThis.fetch;
  globalThis.fetch =
    (() => Promise.resolve(new Response(noPoster, { status: 200 }))) as typeof fetch;
  try {
    const result = await fetchDetail(
      'https://gjtennis.kr/sub5_2_2_view.php?sid=1',
      '광주',
      '힌트제목',
      [],
    );
    assert(result?.tournament, 'tournament should be parsed');
    assertEquals(result.tournament.poster_url, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
