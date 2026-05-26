// clubs-approve: 어드민이 클럽 생성 요청 승인·거절
// POST { club_id, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireAdmin(req);
  if ('error' in auth) return auth.error;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }

  const clubId = body.club_id as string | undefined;
  const action = body.action as string | undefined;
  if (!clubId) return errorResponse('club_id is required', 400);
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be approve|reject', 400);
  }

  const supa = serviceClient();

  const { error } = await supa
    .from('clubs')
    .update({
      status: action === 'approve' ? 'approved' : 'rejected',
      status_reason: (body.reason as string | undefined) ?? null,
      approved_by: auth.user.id,
      approved_at: new Date().toISOString(),
      active: action === 'approve',
    })
    .eq('id', clubId)
    .eq('status', 'pending');

  if (error) return errorResponse(error.message, 500);
  return jsonResponse({ ok: true, action });
});
