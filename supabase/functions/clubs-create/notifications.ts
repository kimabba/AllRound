import type { SupabaseClient } from '@supabase/supabase-js';

import { createNotification, type CreateNotificationInput } from '../_shared/notifications.ts';

interface PendingClubNotification {
  clubId: string;
  clubName: string;
}

interface RejectedClubNotification extends PendingClubNotification {
  ownerId: string;
  reason: string;
}

export type ClubApprovalNotificationKind = 'initial' | 'resubmission';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function adminIdsFromRows(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const ids = new Set<string>();
  for (const row of value) {
    if (!isRecord(row)) continue;
    const id = row.id;
    if (typeof id === 'string' && id.length > 0) ids.add(id);
  }
  return [...ids];
}

export function buildClubApprovalNotification(
  adminId: string,
  club: PendingClubNotification,
  kind: ClubApprovalNotificationKind = 'initial',
): CreateNotificationInput {
  const resubmitted = kind === 'resubmission';
  return {
    userId: adminId,
    type: 'club_approval_request',
    title: resubmitted ? '클럽 재검수 요청' : '새 클럽 승인 요청',
    body: resubmitted
      ? `“${club.clubName}” 클럽이 수정 후 재검수를 요청했습니다.`
      : `“${club.clubName}” 클럽이 승인을 기다리고 있습니다.`,
    referenceType: 'club_approval_request',
    referenceId: club.clubId,
    clubId: club.clubId,
    delivery: 'latest_device',
  };
}

export function buildClubRejectionNotification(
  club: RejectedClubNotification,
): CreateNotificationInput {
  return {
    userId: club.ownerId,
    type: 'club_creation_rejected',
    title: '클럽 생성 요청이 거절되었습니다',
    body: `“${club.clubName}” 거절 사유: ${club.reason}`,
    referenceType: 'club_creation_review',
    referenceId: club.clubId,
    clubId: club.clubId,
    delivery: 'latest_device',
  };
}

export async function notifyClubCreatorOfRejection(
  supabase: SupabaseClient,
  club: RejectedClubNotification,
): Promise<void> {
  const { error: deleteError } = await supabase
    .from('notifications')
    .delete()
    .eq('user_id', club.ownerId)
    .eq('type', 'club_creation_rejected')
    .eq('reference_id', club.clubId);
  if (deleteError) throw new Error('기존 클럽 거절 알림 정리 실패');
  await createNotification(supabase, buildClubRejectionNotification(club));
}

export async function notifyAdminsOfPendingClub(
  supabase: SupabaseClient,
  club: PendingClubNotification,
  kind: ClubApprovalNotificationKind = 'initial',
): Promise<void> {
  const { data, error } = await supabase
    .from('users')
    .select('id')
    .eq('role', 'admin');
  if (error) throw new Error('관리자 계정 조회 실패');

  const adminIds = adminIdsFromRows(data);
  const results = await Promise.allSettled(adminIds.map(async (adminId) => {
    if (kind === 'resubmission') {
      const { error: deleteError } = await supabase
        .from('notifications')
        .delete()
        .eq('user_id', adminId)
        .eq('type', 'club_approval_request')
        .eq('reference_id', club.clubId);
      if (deleteError) throw new Error('기존 관리자 알림 정리 실패');
    }
    await createNotification(
      supabase,
      buildClubApprovalNotification(adminId, club, kind),
    );
  }));
  const failedCount = results.filter((result) => result.status === 'rejected').length;
  if (failedCount > 0) {
    throw new Error(`관리자 알림 ${failedCount}건 생성 실패`);
  }
}
