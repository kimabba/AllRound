// clubs-join: 클럽 가입 신청 / 취소 / 탈퇴 / 강퇴 / 운영 권한 관리
// POST {
//   club_id,
//   action: 'request'|'cancel'|'leave'|'kick'|'set_manager'|'update_monthly_fee'|'update_intro'|'resubmit_review'|'delete_club'|'list_members',
//   message?,
//   target_user_id?,
//   role?,
//   monthly_fee?,
// }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { createNotification } from '../_shared/notifications.ts';
import { serviceClient } from '../_shared/supabase.ts';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringField(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function optionalText(value: unknown, maxLength: number): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string') {
    throw new Error('description must be a string or null');
  }
  const text = value.trim();
  if (text.length > maxLength) {
    throw new Error(`description must be ${maxLength} characters or less`);
  }
  return text.length === 0 ? null : text;
}

function optionalUrlArray(value: unknown): string[] {
  if (value === null || value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new Error('intro_image_urls must be an array');
  }
  if (value.length > 5) {
    throw new Error('intro_image_urls can include up to 5 images');
  }
  return value.map((item) => {
    if (typeof item !== 'string') {
      throw new Error('intro_image_urls must contain only strings');
    }
    const url = item.trim();
    if (!url) throw new Error('intro_image_urls cannot contain empty values');
    try {
      const parsed = new URL(url);
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
        throw new Error();
      }
    } catch {
      throw new Error('intro_image_urls must contain valid http(s) URLs');
    }
    return url;
  });
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let parsedBody: unknown;
  try {
    parsedBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  if (!isRecord(parsedBody)) return errorResponse('Invalid JSON body', 400);

  const body = parsedBody;
  const clubId = stringField(body.club_id);
  const action = stringField(body.action);
  if (!clubId) return errorResponse('club_id is required', 400);
  if (!action) return errorResponse('action is required', 400);

  const supa = serviceClient();
  const userId = auth.user.id;

  async function activeMember(select = 'role') {
    const { data } = await supa
      .from('club_members')
      .select(select)
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .eq('status', 'active')
      .maybeSingle();
    return data as Record<string, unknown> | null;
  }

  async function requireOwner() {
    const member = await activeMember('role');
    if (member?.role !== 'owner') {
      return errorResponse('Only owner can manage this club', 403);
    }
    return null;
  }

  async function isAdmin() {
    const { data } = await supa
      .from('users')
      .select('role')
      .eq('id', userId)
      .maybeSingle();
    return data?.role === 'admin';
  }

  if (action === 'list_members') {
    const member = await activeMember('role');
    const admin = member ? false : await isAdmin();
    if (!member && !admin) {
      return errorResponse('Only active club members can view members', 403);
    }

    const { data, error } = await supa
      .from('club_members')
      .select(
        'user_id, role, can_create_event, can_post_notice, joined_at, users(name)',
      )
      .eq('club_id', clubId)
      .eq('status', 'active')
      .order('joined_at');
    if (error) return errorResponse(error.message, 500);

    return jsonResponse({ members: data ?? [] });
  }

  if (action === 'request') {
    // 클럽이 승인된 상태인지 확인
    const { data: club } = await supa
      .from('clubs')
      .select('id, name, status')
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

    const { data: existingRequest, error: existingRequestError } = await supa
      .from('club_join_requests')
      .select('id, status')
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .maybeSingle();
    if (existingRequestError) {
      return errorResponse(existingRequestError.message, 500);
    }
    if (existingRequest?.status === 'pending') {
      return jsonResponse({
        ok: true,
        action: 'already_pending',
        request_id: existingRequest.id,
      });
    }

    // 가입 신청 (upsert — 취소 후 재신청 허용)
    const { data: joinRequest, error } = await supa
      .from('club_join_requests')
      .upsert({
        club_id: clubId,
        user_id: userId,
        message: stringField(body.message)?.trim() || null,
        status: 'pending',
        reviewed_by: null,
        reviewed_at: null,
      }, { onConflict: 'club_id,user_id' })
      .select('id')
      .single();
    if (error) return errorResponse(error.message, 500);

    const requesterLabel = auth.user.email?.trim() || `사용자 ${userId.slice(0, 8)}`;
    const { data: reviewers } = await supa
      .from('club_members')
      .select('user_id, role')
      .eq('club_id', clubId)
      .eq('status', 'active')
      .in('role', ['owner', 'manager']);

    for (const reviewer of reviewers ?? []) {
      const reviewerId = typeof reviewer.user_id === 'string' ? reviewer.user_id : '';
      if (!reviewerId || reviewerId === userId) continue;
      await createNotification(supa, {
        userId: reviewerId,
        type: 'club_join_request',
        title: '새 클럽 가입 신청',
        body: `${requesterLabel}님이 ${club.name} 가입을 신청했습니다.`,
        referenceType: 'club_join_request',
        referenceId: typeof joinRequest?.id === 'string' ? joinRequest.id : null,
        clubId,
      });
    }

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

  if (action === 'kick') {
    // 강퇴 (owner만, 자기 자신 불가)
    const targetUserId = stringField(body.target_user_id);
    if (!targetUserId) return errorResponse('target_user_id is required', 400);
    if (targetUserId === userId) {
      return errorResponse('Cannot kick yourself', 400);
    }

    const ownerError = await requireOwner();
    if (ownerError) return ownerError;

    const { data: target } = await supa
      .from('club_members')
      .select('role')
      .eq('club_id', clubId)
      .eq('user_id', targetUserId)
      .eq('status', 'active')
      .maybeSingle();
    if (!target) return errorResponse('Target member not found', 404);
    if (target.role === 'owner') {
      return errorResponse('Owner cannot be kicked', 400);
    }

    const { error } = await supa
      .from('club_members')
      .delete()
      .eq('club_id', clubId)
      .eq('user_id', targetUserId)
      .eq('status', 'active');
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true, action: 'kicked' });
  }

  if (action === 'set_manager') {
    const targetUserId = stringField(body.target_user_id);
    const role = stringField(body.role);
    if (!targetUserId) return errorResponse('target_user_id is required', 400);
    if (role !== 'manager' && role !== 'member') {
      return errorResponse('role must be manager or member', 400);
    }
    if (targetUserId === userId) {
      return errorResponse('Owner cannot change their own role', 400);
    }

    const ownerError = await requireOwner();
    if (ownerError) return ownerError;

    const { data: target } = await supa
      .from('club_members')
      .select('role')
      .eq('club_id', clubId)
      .eq('user_id', targetUserId)
      .eq('status', 'active')
      .maybeSingle();
    if (!target) return errorResponse('Target member not found', 404);
    if (target.role === 'owner') {
      return errorResponse('Owner role cannot be changed here', 400);
    }

    const { error } = await supa
      .from('club_members')
      .update({
        role,
        can_kick: false,
        can_create_event: role === 'manager',
        can_post_notice: false,
      })
      .eq('club_id', clubId)
      .eq('user_id', targetUserId)
      .eq('status', 'active');
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true, action: 'role_updated', role });
  }

  if (action === 'update_monthly_fee') {
    const member = await activeMember('role');
    if (member?.role !== 'owner' && member?.role !== 'manager') {
      return errorResponse('Only owner or manager can update monthly fee', 403);
    }

    const fee = body.monthly_fee;
    if (
      fee !== null &&
      (typeof fee !== 'number' || !Number.isInteger(fee) || fee < 0 ||
        fee > 1000000)
    ) {
      return errorResponse(
        'monthly_fee must be an integer between 0 and 1000000 or null',
        400,
      );
    }

    const { data: updatedClub, error } = await supa
      .from('clubs')
      .update({ monthly_fee: fee })
      .eq('id', clubId)
      .in('status', ['approved', 'rejected'])
      .select('id')
      .maybeSingle();
    if (error) return errorResponse(error.message, 500);
    if (!updatedClub) {
      return errorResponse('Club cannot be updated in its current status', 409);
    }
    return jsonResponse({ ok: true, action: 'monthly_fee_updated' });
  }

  if (action === 'update_intro') {
    const member = await activeMember('role');
    if (member?.role !== 'owner' && member?.role !== 'manager') {
      return errorResponse('Only owner or manager can update club intro', 403);
    }

    let description: string | null;
    let introImageUrls: string[];
    try {
      description = optionalText(body.description, 2000);
      introImageUrls = optionalUrlArray(body.intro_image_urls);
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Invalid intro payload';
      return errorResponse(message, 400);
    }

    const { data: updatedClub, error } = await supa
      .from('clubs')
      .update({
        description,
        intro_image_urls: introImageUrls,
      })
      .eq('id', clubId)
      .in('status', ['approved', 'rejected'])
      .select('id')
      .maybeSingle();
    if (error) return errorResponse(error.message, 500);
    if (!updatedClub) {
      return errorResponse('Club cannot be updated in its current status', 409);
    }
    return jsonResponse({ ok: true, action: 'intro_updated' });
  }

  if (action === 'resubmit_review') {
    const ownerError = await requireOwner();
    if (ownerError) return ownerError;

    const { data: club, error: clubError } = await supa
      .from('clubs')
      .select('status,status_reason')
      .eq('id', clubId)
      .maybeSingle();
    if (clubError) return errorResponse(clubError.message, 500);
    if (!club) return errorResponse('Club not found', 404);
    if (club.status !== 'rejected') {
      return errorResponse('Only rejected clubs can be resubmitted', 409);
    }
    if (club.status_reason === 'deleted_by_owner') {
      return errorResponse('Deleted clubs cannot be resubmitted', 409);
    }

    const { data: updatedClub, error: updateError } = await supa
      .from('clubs')
      .update({
        status: 'pending',
        status_reason: null,
        approved_by: null,
        approved_at: null,
      })
      .eq('id', clubId)
      .eq('status', 'rejected')
      .select('id')
      .maybeSingle();
    if (updateError) return errorResponse(updateError.message, 500);
    if (!updatedClub) return errorResponse('Club review status changed', 409);

    return jsonResponse({ ok: true, action: 'review_resubmitted' });
  }

  if (action === 'delete_club') {
    const ownerError = await requireOwner();
    if (ownerError) return ownerError;

    const { error } = await supa
      .from('clubs')
      .update({
        status: 'rejected',
        status_reason: 'deleted_by_owner',
      })
      .eq('id', clubId)
      .in('status', ['pending', 'approved', 'rejected']);
    if (error) return errorResponse(error.message, 500);

    // 삭제된 클럽의 active 멤버십을 정리(left)해 내 클럽/멤버 목록에서 사라지게 한다.
    const { error: memberError } = await supa
      .from('club_members')
      .update({ status: 'left', left_at: new Date().toISOString() })
      .eq('club_id', clubId)
      .eq('status', 'active');
    if (memberError) return errorResponse(memberError.message, 500);

    return jsonResponse({ ok: true, action: 'club_deleted' });
  }

  return errorResponse(
    'action must be request|cancel|leave|kick|set_manager|update_monthly_fee|update_intro|resubmit_review|delete_club|list_members',
    400,
  );
});
