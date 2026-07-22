// clubs-review-join: 클럽장/운영진이 가입 신청 목록 조회·승인·거절
// GET ?club_id=<uuid>
// POST { request_id, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { createNotification } from '../_shared/notifications.ts';
import { serviceClient } from '../_shared/supabase.ts';

function stringField(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function recordField(value: unknown): Record<string, unknown> | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

async function canReviewClub(
  supa: ReturnType<typeof serviceClient>,
  userId: string,
  clubId: string,
): Promise<boolean> {
  const [{ data: member }, { data: profile }] = await Promise.all([
    supa
      .from('club_members')
      .select('role')
      .eq('club_id', clubId)
      .eq('user_id', userId)
      .eq('status', 'active')
      .maybeSingle(),
    supa.from('users').select('role').eq('id', userId).maybeSingle(),
  ]);
  return profile?.role === 'admin' ||
    (member !== null && ['owner', 'manager'].includes(member.role));
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET' && req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  const supa = serviceClient();
  const reviewerId = auth.user.id;

  if (req.method === 'GET') {
    const clubId = new URL(req.url).searchParams.get('club_id')?.trim() ?? '';
    if (!clubId) return errorResponse('club_id is required', 400);
    if (!(await canReviewClub(supa, reviewerId, clubId))) {
      return errorResponse('Forbidden: owner/manager or admin only', 403);
    }

    const { data: rawRequests, error: requestsError } = await supa
      .from('club_join_requests')
      .select('id, user_id, message, created_at')
      .eq('club_id', clubId)
      .eq('status', 'pending')
      .order('created_at');
    if (requestsError) return errorResponse('JOIN_REQUEST_LIST_FAILED', 500);

    const requests = Array.isArray(rawRequests)
      ? rawRequests.map(recordField).filter(
        (row): row is Record<string, unknown> => row !== null,
      )
      : [];
    const userIds = [
      ...new Set(
        requests.map((row) => stringField(row.user_id)).filter(
          (id): id is string => id !== null,
        ),
      ),
    ];
    const profiles = new Map<string, Record<string, unknown>>();
    if (userIds.length > 0) {
      const { data: rawProfiles, error: profilesError } = await supa
        .from('users')
        .select('id, nickname, name, avatar_url, primary_region')
        .in('id', userIds);
      if (profilesError) return errorResponse('JOIN_REQUEST_PROFILE_FAILED', 500);
      if (Array.isArray(rawProfiles)) {
        for (const value of rawProfiles) {
          const profile = recordField(value);
          const id = stringField(profile?.id);
          if (profile && id) profiles.set(id, profile);
        }
      }
    }

    return jsonResponse({
      requests: requests.map((request) => {
        const userId = stringField(request.user_id);
        const profile = userId === null ? null : profiles.get(userId) ?? null;
        return {
          ...request,
          applicant: profile === null ? null : {
            display_name: stringField(profile.nickname) ??
              stringField(profile.name),
            avatar_url: stringField(profile.avatar_url),
            primary_region: stringField(profile.primary_region),
          },
        };
      }),
    });
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  const body = recordField(rawBody);
  if (!body) return errorResponse('Invalid JSON', 400);
  const requestId = stringField(body.request_id);
  const action = stringField(body.action);
  if (!requestId) return errorResponse('request_id is required', 400);
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be approve|reject', 400);
  }

  // 신청 정보 조회
  const { data: jr, error: jrErr } = await supa
    .from('club_join_requests')
    .select('id, club_id, user_id, status, clubs(name)')
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

  // 승인이면 멤버 추가를 먼저 수행한다.
  // 멤버 upsert 가 실패하면 신청을 pending 으로 남겨 재시도 가능하게 한다.
  // (상태를 먼저 approved 로 바꾸면, 멤버 추가 실패 시 'Already reviewed' 409 로
  //  재시도가 막혀 멤버가 영영 추가되지 않는 교착이 발생한다.)
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

  // 신청 상태 업데이트 (멤버 upsert 는 멱등이므로 이 단계 실패 후 재시도해도 안전)
  const { error: updateErr } = await supa
    .from('club_join_requests')
    .update({
      status: action === 'approve' ? 'approved' : 'rejected',
      reviewed_by: reviewerId,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', requestId);

  if (updateErr) return errorResponse(updateErr.message, 500);

  const clubName = jr.clubs && typeof jr.clubs === 'object' && 'name' in jr.clubs &&
      typeof jr.clubs.name === 'string'
    ? jr.clubs.name
    : '클럽';
  const approved = action === 'approve';
  await createNotification(supa, {
    userId: jr.user_id,
    type: approved ? 'club_join_approved' : 'club_join_rejected',
    title: approved ? '클럽 가입이 승인되었습니다' : '클럽 가입 신청이 거절되었습니다',
    body: approved
      ? `${clubName} 가입이 승인되었습니다. 이제 클럽 멤버 화면을 확인할 수 있습니다.`
      : `${clubName} 가입 신청이 거절되었습니다. 운영진에게 문의해 주세요.`,
    referenceType: 'club_join_request',
    referenceId: jr.id,
    clubId: jr.club_id,
  });

  return jsonResponse({ ok: true, action });
});
