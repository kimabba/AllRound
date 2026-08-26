// _shared/crawler/poster.ts
//
// 상세 본문의 포스터 이미지 URL 추출 공용 헬퍼 (P6).
// 원래 kta_sportsforall.ts 에만 있던 extractPosterUrl 을 gj/jn·KATO 파서에서도
// 쓰도록 승격했다. OCR 은 여기서 하지 않는다 — URL 만 남기고, 이미지 판독은
// format-pending 의 포스터 보완 단계(Gemini vision)가 검수 스테이징 경유로만 한다.

// 사이트 UI 이미지(로고·아이콘·버튼·협찬배너 등)는 포스터가 아니다. 파일명·경로
// 세그먼트가 구분자(/, ., _, -)로 감싸인 경우만 매치해 'naver' 같은 정상 단어를
// 오인하지 않는다. logo 는 변형이 흔해(kato.kr 실측 logox3.png) 접두 매치를 허용하고,
// commercials 는 KATO 협찬배너 경로(/uploads/commercials/*, 실측 0299 외 3건)다.
const UI_IMAGE_PATTERN =
  /(?:^|[\/._-])(logo\w*|icons?|ico|btn|buttons?|bullet|spacer|blank|banners?|commercials?|sponsors?|menu|nav|gnb|lnb|snb|common|layout|emoticon)(?:[\/._-]|\d|$)/i;

// 게시판 첨부·에디터 업로드 경로는 협회가 올린 포스터일 확률이 높아 우선한다.
// uploads 복수형도 실존한다(kato.kr /uploads/*).
const UPLOAD_PATH_PATTERN = /(?:^|[\/._-])(uploads?|editor|attach|files?|data)(?:[\/._-]|\d|$)/i;

/**
 * HTML 조각에서 첫 유효 포스터 이미지 URL 을 절대경로로 뽑는다.
 * - data: URI·UI 이미지(로고 등)는 제외.
 * - 업로드 경로(uploads/editor/data 등) 이미지가 있으면 그쪽을 우선한다
 *   (사이트 chrome 이미지가 앞에 오는 페이지 대비).
 * - requireUploadPath: 업로드 경로 이미지가 없으면 null. 본문 컨테이너로 범위를
 *   못 좁혀 전체 HTML 을 훑는 파서(KATO)가 chrome 이미지를 줍지 않게 한다.
 */
export function extractPosterUrl(
  html: string | null | undefined,
  baseUrl: string,
  opts: { requireUploadPath?: boolean } = {},
): string | null {
  if (!html) return null;
  const candidates: string[] = [];
  for (const m of html.matchAll(/<img[^>]+src=["']([^"']+)["']/gi)) {
    const src = m[1].trim();
    if (!src || src.startsWith('data:')) continue;
    if (UI_IMAGE_PATTERN.test(src)) continue;
    let absolute: URL;
    try {
      absolute = new URL(src, baseUrl);
    } catch {
      continue;
    }
    if (absolute.protocol !== 'http:' && absolute.protocol !== 'https:') continue;
    candidates.push(absolute.toString());
  }
  if (candidates.length === 0) return null;
  const uploaded = candidates.find((url) => UPLOAD_PATH_PATTERN.test(new URL(url).pathname));
  if (opts.requireUploadPath) return uploaded ?? null;
  return uploaded ?? candidates[0];
}
