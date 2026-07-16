// clubs-approve: 어드민이 클럽 생성 요청 승인·거절
// POST { club_id|club_ids, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseClubIds(body: Record<string, unknown>): string[] {
  const candidates = Array.isArray(body.club_ids) ? body.club_ids : [body.club_id];

  return [
    ...new Set(
      candidates
        .filter((value): value is string => typeof value === 'string')
        .map((value) => value.trim())
        .filter((value) => value.length > 0),
    ),
  ];
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireAdmin(req);
  if ('error' in auth) return auth.error;

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  if (!isRecord(rawBody)) return errorResponse('Invalid JSON body', 400);

  const clubIds = parseClubIds(rawBody);
  const action = rawBody.action;
  if (clubIds.length === 0) {
    return errorResponse('club_id or club_ids is required', 400);
  }
  if (clubIds.length > 100) {
    return errorResponse('A maximum of 100 clubs can be reviewed at once', 400);
  }
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be approve|reject', 400);
  }

  const reason = typeof rawBody.reason === 'string' ? rawBody.reason.trim() : '';
  if (action === 'reject' && reason.length === 0) {
    return errorResponse('reason is required when rejecting clubs', 400);
  }

  const supa = serviceClient();

  if (action === 'approve') {
    const { data: pendingClubs, error: pendingClubsError } = await supa
      .from('clubs')
      .select('id, created_by')
      .in('id', clubIds)
      .eq('status', 'pending');
    if (pendingClubsError) return errorResponse(pendingClubsError.message, 500);
    if (!pendingClubs || pendingClubs.length === 0) {
      return errorResponse('No pending clubs were found', 409);
    }

    const ownerMemberships = pendingClubs
      .filter((club): club is { id: string; created_by: string } =>
        typeof club.created_by === 'string'
      )
      .map((club) => ({
        club_id: club.id,
        user_id: club.created_by,
        role: 'owner',
        status: 'active',
        left_at: null,
      }));

    if (ownerMemberships.length > 0) {
      const { error: membershipError } = await supa
        .from('club_members')
        .upsert(ownerMemberships, { onConflict: 'club_id,user_id' });
      if (membershipError) return errorResponse(membershipError.message, 500);
    }
  }

  const { data, error } = await supa
    .from('clubs')
    .update({
      status: action === 'approve' ? 'approved' : 'rejected',
      status_reason: action === 'reject' ? reason : null,
      approved_by: auth.user.id,
      approved_at: new Date().toISOString(),
    })
    .in('id', clubIds)
    .eq('status', 'pending')
    .select('id');

  if (error) return errorResponse(error.message, 500);
  if (!data || data.length === 0) {
    return errorResponse('No pending clubs were found', 409);
  }

  return jsonResponse({ ok: true, action, count: data.length });
});
