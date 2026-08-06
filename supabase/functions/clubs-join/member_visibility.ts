export function canListClubMembers(input: {
  isActiveMember: boolean;
  isAdmin: boolean;
  clubStatus: unknown;
  isBanned?: boolean;
}): boolean {
  if (input.isBanned) return false;
  return input.isActiveMember || input.isAdmin || input.clubStatus === 'approved';
}
