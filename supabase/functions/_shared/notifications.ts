import { SupabaseClient } from '@supabase/supabase-js';
import { sendFcm } from './fcm.ts';
import type { FcmNotificationInput } from './fcm.ts';

export interface DeviceTokenRow {
  token: string;
  platform: 'ios' | 'android' | 'web';
}

export interface CreateNotificationInput {
  userId: string;
  type: string;
  title: string;
  body?: string | null;
  referenceType?: string | null;
  referenceId?: string | null;
  clubId?: string | null;
}

export async function createNotification(
  supabase: SupabaseClient,
  input: CreateNotificationInput,
): Promise<void> {
  const { data: tokenRows } = await supabase
    .from('device_tokens')
    .select('token, platform')
    .eq('user_id', input.userId)
    .eq('enabled', true);

  const tokens = ((tokenRows ?? []) as DeviceTokenRow[]).map((row) => row.token);
  const body = input.body?.trim() ?? '';

  const pushInput: FcmNotificationInput = {
    title: input.title,
    body,
    type: input.type,
    referenceType: input.referenceType,
    referenceId: input.referenceId,
    clubId: input.clubId,
  };
  const result = await sendFcm(tokens, pushInput);
  const status = result.status === 'skipped' ? 'pending' : result.status;
  const sentAt = result.status === 'sent' ? new Date().toISOString() : null;

  const { error } = await supabase.from('notifications').insert({
    user_id: input.userId,
    type: input.type,
    title: input.title,
    body: body.length === 0 ? null : body,
    reference_type: input.referenceType ?? null,
    reference_id: input.referenceId ?? null,
    club_id: input.clubId ?? null,
    status,
    error: result.error,
    sent_at: sentAt,
  });

  if (error) throw error;
}
