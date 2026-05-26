// clubs-join: 클럽 가입 신청 / 취소 / 탈퇴
// POST { club_id, action: 'request'|'cancel'|'leave', message? }

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

  const clubId = body.club_id as string | undefined;
  const action = body.action as string | undefined;
  if (!clubId) return errorResponse('club_id is required', 400);
  if (!action) return errorResponse('action is required', 400);

  const supa = serviceClient();
  const userId = auth.user.id;

  if (action === 'request') {
    // 클럽이 승인된 상태인지 확인
    const { data: club } = await supa
      .from('clubs')
      .select('id, status')
      .eq('id', clubId)
      .single();
    if (!club || club.status !== 'approved') {
      return errorResponse('Club not found or not approved', 404);
    }

    // 이미 멤버인지 확인
    const { data: existing } = await supa
      .from('club_members')
      .select('id, status')
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .maybeSingle();
    if (existing?.status === 'active') {
      return errorResponse('Already a member', 409);
    }

    // 가입 신청 (upsert — 취소 후 재신청 허용)
    const { error } = await supa
      .from('club_join_requests')
      .upsert({
        club_id: clubId,
        user_id: userId,
        message: (body.message as string | undefined)?.trim() || null,
        status: 'pending',
        reviewed_by: null,
        reviewed_at: null,
      }, { onConflict: 'club_id,user_id' });
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true, action: 'requested' });
  }

  if (action === 'cancel') {
    // 신청 취소 (pending 상태만)
    const { error } = await supa
      .from('club_join_requests')
      .delete()
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .eq('status', 'pending');
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true, action: 'cancelled' });
  }

  if (action === 'leave') {
    // 탈퇴 (owner는 불가)
    const { data: member } = await supa
      .from('club_members')
      .select('role')
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .maybeSingle();
    if (member?.role === 'owner') {
      return errorResponse('Owner cannot leave. Transfer ownership first.', 400);
    }
    const { error } = await supa
      .from('club_members')
      .update({ status: 'left', left_at: new Date().toISOString() })
      .eq('club_id', clubId)
      .eq('user_id', userId);
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true, action: 'left' });
  }

  return errorResponse('action must be request|cancel|leave', 400);
});
