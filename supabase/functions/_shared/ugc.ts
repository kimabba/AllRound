import type { SupabaseClient } from '@supabase/supabase-js';

export type UgcAction = 'club_join' | 'community_create';

export function penaltyTypesForAction(action: UgcAction): string[] {
  return action === 'club_join'
    ? ['club_join_restriction', 'community_restriction']
    : ['community_restriction'];
}

export async function ugcAccessError(
  supabase: SupabaseClient,
  userId: string,
  action: UgcAction,
): Promise<string | null> {
  const { data: user, error: userError } = await supabase
    .from('users')
    .select('ugc_terms_version, ugc_terms_accepted_at')
    .eq('id', userId)
    .maybeSingle();
  if (userError) return 'UGC_ACCESS_CHECK_FAILED';
  if (
    user?.ugc_terms_version !== '2026-07-15' ||
    typeof user.ugc_terms_accepted_at !== 'string'
  ) {
    return 'UGC_TERMS_REQUIRED';
  }

  const now = new Date().toISOString();
  const { data: penalties, error: penaltyError } = await supabase
    .from('user_penalties')
    .select('id')
    .eq('user_id', userId)
    .in('penalty_type', penaltyTypesForAction(action))
    .is('revoked_at', null)
    .lte('starts_at', now)
    .or(`ends_at.is.null,ends_at.gt.${now}`)
    .limit(1);
  if (penaltyError) return 'UGC_ACCESS_CHECK_FAILED';
  return penalties && penalties.length > 0 ? 'UGC_ACTION_RESTRICTED' : null;
}
