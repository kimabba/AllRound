// clubs-approve: 어드민이 클럽 생성 요청 승인·거절
// POST { club_id|club_ids, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { notifyClubCreatorOfRejection } from '../clubs-create/notifications.ts';

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

Deno.serve(withCors(async (req) => {
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
    .select('id, name, created_by, status_reason');

  if (error) return errorResponse(error.message, 500);
  if (!data || data.length === 0) {
    const { data: current } = await supa
      .from('clubs')
      .select('id, name, status, status_reason, approved_by, approved_at')
      .in('id', clubIds);
    return jsonResponse({
      error: '이미 다른 관리자가 처리한 요청입니다.',
      clubs: current ?? [],
    }, { status: 409 });
  }
  if (action === 'reject') {
    const notificationResults = await Promise.allSettled(
      data.map((club) => {
        const ownerId = typeof club.created_by === 'string' ? club.created_by : '';
        const clubName = typeof club.name === 'string' ? club.name : '클럽';
        const rejectionReason = typeof club.status_reason === 'string'
          ? club.status_reason
          : reason;
        if (ownerId.length === 0) return Promise.resolve();
        return notifyClubCreatorOfRejection(supa, {
          clubId: club.id,
          clubName,
          ownerId,
          reason: rejectionReason,
        });
      }),
    );
    const failedCount = notificationResults.filter((result) => result.status === 'rejected').length;
    if (failedCount > 0) {
      console.error(`Failed to create ${failedCount} club rejection notifications`);
    }
  }
  return jsonResponse({
    ok: true,
    action,
    count: data.length,
    skipped_count: clubIds.length - data.length,
  });
}));
