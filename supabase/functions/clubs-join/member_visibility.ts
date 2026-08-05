export function canListClubMembers(input: {
  isActiveMember: boolean;
  isAdmin: boolean;
  clubStatus: unknown;
}): boolean {
  return input.isActiveMember || input.isAdmin || input.clubStatus === 'approved';
}
