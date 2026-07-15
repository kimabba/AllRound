export interface AdminClubApproval {
  status: 'approved';
  status_reason: null;
  approved_by: string;
  approved_at: string;
}

export function buildAdminClubApproval(
  isAdmin: boolean,
  userId: string,
  approvedAt: string,
): AdminClubApproval | null {
  if (!isAdmin) return null;
  return {
    status: 'approved',
    status_reason: null,
    approved_by: userId,
    approved_at: approvedAt,
  };
}
