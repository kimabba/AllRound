import { SupabaseClient } from '@supabase/supabase-js';

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

export function buildFcmPayload(
  tokens: string[],
  input: CreateNotificationInput,
) {
  return {
    registration_ids: tokens,
    notification: {
      title: input.title,
      body: input.body?.trim() ?? '',
    },
    data: {
      type: input.type,
      reference_type: input.referenceType ?? '',
      reference_id: input.referenceId ?? '',
      club_id: input.clubId ?? '',
    },
    priority: 'high',
  };
}

async function sendFcm(
  tokens: string[],
  input: CreateNotificationInput,
): Promise<boolean> {
  const serverKey = Deno.env.get('FCM_SERVER_KEY');
  if (!serverKey || tokens.length === 0) return false;

  const res = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${serverKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(buildFcmPayload(tokens, input)),
  });
  return res.ok;
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

  let status: 'pending' | 'sent' | 'failed' = 'sent';
  let errorText: string | null = null;
  let sentAt: string | null = null;

  if (tokens.length > 0 && body.length > 0 && Deno.env.get('FCM_SERVER_KEY')) {
    try {
      const ok = await sendFcm(tokens, input);
      status = ok ? 'sent' : 'failed';
      sentAt = ok ? new Date().toISOString() : null;
    } catch (error) {
      status = 'failed';
      errorText = error instanceof Error ? error.message : 'Unknown FCM error';
    }
  }

  const { error } = await supabase.from('notifications').insert({
    user_id: input.userId,
    type: input.type,
    title: input.title,
    body: body.length === 0 ? null : body,
    reference_type: input.referenceType ?? null,
    reference_id: input.referenceId ?? null,
    club_id: input.clubId ?? null,
    status,
    error: errorText,
    sent_at: sentAt,
  });

  if (error) throw error;
}
