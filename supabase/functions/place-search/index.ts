import { requireUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { serviceClient } from '../_shared/supabase.ts';
import {
  type JusoAddress,
  normalizePlaceQuery,
  parseJusoCoordinateResponse,
  parseJusoSearchResponse,
  toPlaceSearchResult,
} from './juso.ts';

const addressEndpoint = 'https://business.juso.go.kr/addrlink/addrLinkApi.do';
const coordinateEndpoint = 'https://business.juso.go.kr/addrlink/addrCoordApi.do';

async function fetchCoordinate(address: JusoAddress, apiKey: string, signal: AbortSignal) {
  const url = new URL(coordinateEndpoint);
  url.searchParams.set('confmKey', apiKey);
  url.searchParams.set('admCd', address.admCd);
  url.searchParams.set('rnMgtSn', address.rnMgtSn);
  url.searchParams.set('udrtYn', address.udrtYn);
  url.searchParams.set('buldMnnm', address.buldMnnm);
  url.searchParams.set('buldSlno', address.buldSlno);
  url.searchParams.set('resultType', 'json');

  const response = await fetch(url, { signal });
  if (!response.ok) return null;
  const parsed = parseJusoCoordinateResponse(await response.json() as unknown);
  if (parsed.errorCode !== '0' || !parsed.coordinate) return null;
  return toPlaceSearchResult(address, parsed.coordinate);
}

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

  const searchApiKey = Deno.env.get('JUSO_SEARCH_API_KEY');
  const coordinateApiKey = Deno.env.get('JUSO_COORD_API_KEY');
  if (!searchApiKey || !coordinateApiKey) {
    console.error('[place-search] JUSO_SEARCH_API_KEY or JUSO_COORD_API_KEY is not configured');
    return errorResponse('장소 검색 설정이 완료되지 않았습니다.', 503);
  }

  const url = new URL(addressEndpoint);
  url.searchParams.set('confmKey', searchApiKey);
  url.searchParams.set('currentPage', '1');
  url.searchParams.set('countPerPage', '10');
  url.searchParams.set('keyword', query);
  url.searchParams.set('resultType', 'json');
  url.searchParams.set('addInfoYn', 'Y');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) {
      console.error(`[place-search] Juso address search failed with ${response.status}`);
      return errorResponse('장소 검색에 실패했습니다. 잠시 후 다시 시도해주세요.', 502);
    }
    const parsed = parseJusoSearchResponse(await response.json() as unknown);
    if (parsed.errorCode !== '0') {
      console.error(`[place-search] Juso address search error ${parsed.errorCode}`);
      return errorResponse('주소 검색에 실패했습니다. 검색어를 확인해주세요.', 502);
    }
    const places = (await Promise.all(
      parsed.addresses.map((address) =>
        fetchCoordinate(address, coordinateApiKey, controller.signal)
      ),
    )).filter((place) => place !== null);
    return jsonResponse({ places });
  } catch (error) {
    console.error('[place-search] Juso API request failed', error);
    return errorResponse('장소 검색 서버에 연결할 수 없습니다.', 502);
  } finally {
    clearTimeout(timeout);
  }
}));
