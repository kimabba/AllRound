import type { SupabaseClient } from '@supabase/supabase-js';

import { createNotification, type CreateNotificationInput } from '../_shared/notifications.ts';

interface PendingClubNotification {
  clubId: string;
  clubName: string;
}

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
): CreateNotificationInput {
  return {
    userId: adminId,
    type: 'club_approval_request',
    title: '새 클럽 승인 요청',
    body: `“${club.clubName}” 클럽이 승인을 기다리고 있습니다.`,
    referenceType: 'club_approval_request',
    referenceId: club.clubId,
    clubId: club.clubId,
  };
}

export async function notifyAdminsOfPendingClub(
  supabase: SupabaseClient,
  club: PendingClubNotification,
): Promise<void> {
  const { data, error } = await supabase
    .from('users')
    .select('id')
    .eq('role', 'admin');
  if (error) throw new Error('관리자 계정 조회 실패');

  const adminIds = adminIdsFromRows(data);
  const results = await Promise.allSettled(
    adminIds.map((adminId) =>
      createNotification(
        supabase,
        buildClubApprovalNotification(adminId, club),
      )
    ),
  );
  const failedCount = results.filter((result) => result.status === 'rejected').length;
  if (failedCount > 0) {
    throw new Error(`관리자 알림 ${failedCount}건 생성 실패`);
  }
}
