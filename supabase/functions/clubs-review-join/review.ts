// clubs-review-join 권한 판정·승인/거절 플로우 (index.ts 에서 분리해 단위 테스트 가능하게 함)

import { createNotification } from '../_shared/notifications.ts';
import { serviceClient } from '../_shared/supabase.ts';

export async function canReviewClub(
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

export type ReviewJoinResult =
  | { ok: true; action: 'approve' | 'reject' }
  | { ok: false; status: number; message: string };

export async function reviewJoin(
  supa: ReturnType<typeof serviceClient>,
  { requestId, action, reviewerId }: {
    requestId: string;
    action: 'approve' | 'reject';
    reviewerId: string;
  },
): Promise<ReviewJoinResult> {
  // 신청 정보 조회
  const { data: jr, error: jrErr } = await supa
    .from('club_join_requests')
    .select('id, club_id, user_id, status, clubs(name)')
    .eq('id', requestId)
    .single();

  if (jrErr || !jr) {
    return { ok: false, status: 404, message: 'Join request not found' };
  }
  if (jr.status !== 'pending') {
    return { ok: false, status: 409, message: 'Already reviewed' };
  }

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
    return {
      ok: false,
      status: 403,
      message: 'Forbidden: owner/manager or admin only',
    };
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
    if (memberErr) return { ok: false, status: 500, message: memberErr.message };
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

  if (updateErr) return { ok: false, status: 500, message: updateErr.message };

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

  return { ok: true, action };
}
