// clubs-review-join: 클럽장/운영진이 가입 신청 승인·거절
// POST { request_id, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }

  const requestId = body.request_id as string | undefined;
  const action = body.action as string | undefined;
  if (!requestId) return errorResponse('request_id is required', 400);
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be approve|reject', 400);
  }

  const supa = serviceClient();
  const reviewerId = auth.user.id;

  // 신청 정보 조회
  const { data: jr, error: jrErr } = await supa
    .from('club_join_requests')
    .select('id, club_id, user_id, status')
    .eq('id', requestId)
    .single();

  if (jrErr || !jr) return errorResponse('Join request not found', 404);
  if (jr.status !== 'pending') return errorResponse('Already reviewed', 409);

  // 검토자가 해당 클럽의 owner/manager 또는 admin인지 확인
  const { data: member } = await supa
    .from('club_members')
    .select('role')
    .eq('club_id', jr.club_id)
    .eq('user_id', reviewerId)
    .eq('status', 'active')
    .maybeSingle();

  const { data: profile } = await supa
    .from('users')
    .select('role')
    .eq('id', reviewerId)
    .maybeSingle();
  const isAdmin = profile?.role === 'admin';

  if (!isAdmin && (!member || !['owner', 'manager'].includes(member.role))) {
    return errorResponse('Forbidden: owner/manager or admin only', 403);
  }

  // 신청 상태 업데이트
  const { error: updateErr } = await supa
    .from('club_join_requests')
    .update({
      status: action === 'approve' ? 'approved' : 'rejected',
      reviewed_by: reviewerId,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', requestId);

  if (updateErr) return errorResponse(updateErr.message, 500);

  // 승인이면 club_members에 추가
  if (action === 'approve') {
    const { error: memberErr } = await supa
      .from('club_members')
      .upsert({
        club_id: jr.club_id,
        user_id: jr.user_id,
        role: 'member',
        status: 'active',
        joined_at: new Date().toISOString(),
      }, { onConflict: 'club_id,user_id' });
    if (memberErr) return errorResponse(memberErr.message, 500);
  }

  return jsonResponse({ ok: true, action });
});
