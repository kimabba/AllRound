import { requireUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { normalizePlaceQuery, parseKakaoPlaces } from './kakao.ts';

const kakaoEndpoint = 'https://dapi.kakao.com/v2/local/search/keyword.json';

Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  const denied = await checkRateLimit(serviceClient(), auth.user.id, {
    bucket: 'place-search',
    maxPerWindow: 30,
    windowSeconds: 60,
  });
  if (denied) return denied;

  const query = normalizePlaceQuery(new URL(req.url).searchParams.get('q'));
  if (!query) return errorResponse('검색어는 2자 이상 80자 이하로 입력해주세요.', 400);

  const apiKey = Deno.env.get('KAKAO_REST_API_KEY');
  if (!apiKey) {
    console.error('[place-search] KAKAO_REST_API_KEY is not configured');
    return errorResponse('장소 검색 설정이 완료되지 않았습니다.', 503);
  }

  const url = new URL(kakaoEndpoint);
  url.searchParams.set('query', query);
  url.searchParams.set('size', '15');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch(url, {
      headers: { Authorization: `KakaoAK ${apiKey}` },
      signal: controller.signal,
    });
    if (!response.ok) {
      console.error(`[place-search] Kakao Local failed with ${response.status}`);
      return errorResponse('장소 검색에 실패했습니다. 잠시 후 다시 시도해주세요.', 502);
    }
    const body: unknown = await response.json();
    return jsonResponse({ places: parseKakaoPlaces(body) });
  } catch (error) {
    console.error('[place-search] Kakao Local request failed', error);
    return errorResponse('장소 검색 서버에 연결할 수 없습니다.', 502);
  } finally {
    clearTimeout(timeout);
  }
}));
