// supabase/functions/crawl-tennis-korea/index.ts
// ⚠️ DEPRECATED (Phase 2): 이 함수는 thin wrapper 로 변경되었다.
//
// 실제 크롤 로직은 _shared/crawler/parsers/tennis_korea_board.ts 로 이동했고,
// 단일 진입점은 'crawl-dispatch' Edge Function 이다.
//
// 외부 호출 호환성 유지를 위해 본 endpoint 는 보존하되,
// 내부적으로 crawl-dispatch (POST { slug, force: true }) 를 forward 한다.
// dispatcher 의 응답 body 와 status 를 그대로 relay (B5 — Codex 검토):
//   - 404 (source not found / disabled) → 404 그대로
//   - 500 (parser 실패) → 500 그대로
//   - 200 (정상) → 200 + executed/skipped/errors 본문 보존
// 200 으로 하드코딩하면 dispatcher 의 실패가 호출자에게 가려진다.
//
// Phase 4 에서 호출처가 모두 dispatcher 로 이관되면 디렉토리를 삭제할 예정.

import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { corsHeaders, errorResponse, preflight } from '../_shared/cors.ts';

const SLUG = 'tennis-korea';

function dispatchUrl(req: Request): string {
  const baseEnv = Deno.env.get('SUPABASE_URL');
  if (baseEnv) {
    return `${baseEnv.replace(/\/$/, '')}/functions/v1/crawl-dispatch`;
  }
  const u = new URL(req.url);
  return `${u.origin}/functions/v1/crawl-dispatch`;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const authHeader = req.headers.get('Authorization') ?? '';
  try {
    const res = await fetch(dispatchUrl(req), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(authHeader ? { Authorization: authHeader } : {}),
      },
      body: JSON.stringify({ slug: SLUG, force: true }),
    });
    // B5: dispatcher 응답을 그대로 relay (status + body 보존)
    const bodyText = await res.text();
    return new Response(bodyText, {
      status: res.status,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders,
      },
    });
  } catch (e) {
    return errorResponse(`dispatch forward error: ${(e as Error).message}`, 500);
  }
});
