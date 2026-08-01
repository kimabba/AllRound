// CORS 정책 (JY-95).
//
// 이 API 를 브라우저에서 부르는 곳은 로컬 개발 웹뿐이다(`make web` :8080, `make admin` :3000 —
// 둘 다 프로덕션 Supabase 를 호출한다). 모바일 앱은 Origin 헤더를 보내지 않아 CORS 와 무관하다.
// 프로덕션 웹 도메인은 아직 없다(JY-81 웹빌드는 로컬 전용).
//
// 허용 대상이 둘 이상인데 ACAO 헤더에는 오리진을 하나만 실을 수 있다. 그래서 요청 Origin 이
// 허용 목록에 있으면 그것을 그대로 되돌려주고(+`Vary: Origin`), 없으면 ACAO 를 아예 붙이지
// 않는다 — 브라우저가 응답을 읽지 못한다.
//
// CORS_ALLOW_ORIGIN: 쉼표 구분 오리진 목록. 미설정이면 '*'(로컬 개발 편의). 프로덕션에는 반드시
// 설정한다 — 미설정을 조용히 넘기지 않도록 부팅 시 경고를 남긴다.

const rawAllowList = Deno.env.get('CORS_ALLOW_ORIGIN') ?? '';
const allowList = rawAllowList.split(',').map((s) => s.trim()).filter(Boolean);
const allowAny = allowList.length === 0 || allowList.includes('*');

if (allowAny) {
  console.warn(
    'CORS_ALLOW_ORIGIN 미설정 — 모든 오리진을 허용한다. 프로덕션에서는 반드시 설정할 것 (JY-95).',
  );
}

const baseHeaders: Record<string, string> = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};

/**
 * 요청 Origin 에 돌려줄 ACAO 값. 허용되지 않으면 null(헤더를 붙이지 않는다).
 * 허용 목록을 인자로 받는 순수 함수 — 모듈 로드 시 고정되는 env 와 분리해 테스트한다.
 */
export function matchOrigin(origin: string | null, list: string[]): string | null {
  if (list.length === 0 || list.includes('*')) return origin ?? '*';
  if (!origin) return null; // 브라우저가 아닌 호출(모바일·서버) — CORS 헤더가 필요 없다.
  return list.includes(origin) ? origin : null;
}

export function resolveAllowedOrigin(origin: string | null): string | null {
  return matchOrigin(origin, allowList);
}

/**
 * 응답에 CORS 헤더를 입힌다. 오리진 판정에 요청이 필요해 핸들러 바깥에서 한 번에 적용한다
 * (`Deno.serve(withCors(handler))`) — 개별 응답 생성부를 전부 고치지 않기 위함.
 */
export function withCors(
  handler: (req: Request) => Response | Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const res = await handler(req);
    const headers = new Headers(res.headers);
    for (const [key, value] of Object.entries(baseHeaders)) headers.set(key, value);

    const allowed = resolveAllowedOrigin(req.headers.get('Origin'));
    if (allowed) headers.set('Access-Control-Allow-Origin', allowed);
    else headers.delete('Access-Control-Allow-Origin');
    // 오리진마다 응답 헤더가 달라지므로 캐시가 섞이지 않게 한다.
    headers.append('Vary', 'Origin');

    return new Response(res.body, {
      status: res.status,
      statusText: res.statusText,
      headers,
    });
  };
}

/**
 * ACAO 를 뺀 공통 CORS 헤더. 스트리밍 응답처럼 jsonResponse 를 못 쓰는 곳에서 직접 편다.
 * 오리진 헤더는 withCors 가 응답 단계에서 붙인다.
 */
export const corsHeaders: Record<string, string> = { ...baseHeaders };

export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: baseHeaders });
  }
  return null;
}

export function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...baseHeaders,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

export function errorResponse(message: string, status = 400, extra: Record<string, unknown> = {}) {
  return jsonResponse({ error: message, ...extra }, { status });
}
