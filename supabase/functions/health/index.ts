import { jsonResponse, preflight, withCors } from '../_shared/cors.ts';

Deno.serve(withCors((req) => {
  const pre = preflight(req);
  if (pre) return pre;
  return jsonResponse({ status: 'ok', service: 'match-up', ts: new Date().toISOString() });
}));
