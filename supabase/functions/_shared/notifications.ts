import { SupabaseClient } from '@supabase/supabase-js';
import { sendFcm } from './fcm.ts';
import type { FcmNotificationInput } from './fcm.ts';

export interface DeviceTokenRow {
  token: string;
  platform: 'ios' | 'android' | 'web';
  sound_enabled: boolean;
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
    .select('token, platform, sound_enabled')
    .eq('user_id', input.userId)
    .eq('enabled', true);

  const targets = ((tokenRows ?? []) as DeviceTokenRow[]).map((row) => ({
    token: row.token,
    soundEnabled: row.sound_enabled,
  }));
  const body = input.body?.trim() ?? '';

  const pushInput: FcmNotificationInput = {
    title: input.title,
    body,
    type: input.type,
    referenceType: input.referenceType,
    referenceId: input.referenceId,
    clubId: input.clubId,
  };
  const result = await sendFcm(targets, pushInput);
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

export interface ReminderAttemptInput {
  userId: string;
  type: string;
  title: string;
  body: string;
  referenceType: string;
  referenceId: string;
  clubId?: string | null;
}

export type ReminderOutcome = 'sent' | 'failed' | 'skipped_raced';

/**
 * 주기적으로 재확인되는 리마인더(대회 D-3/마감일, 클럽 모임 D-1)를 원자적으로
 * 선점한 뒤에만 발송한다.
 *
 * notify-cron 은 매시간 같은 후보를 다시 훑고, 'pending'(그때 기기 토큰이
 * 없었음) 행은 재시도 대상이다. "있으면 스킵" 만으로는 확인·발송·기록 사이에
 * 레이스가 생겨 두 실행이 겹치면 같은 사용자에게 중복 발송될 수 있다(코드
 * 리뷰 지적). 그래서 sendFcm 은 아래 순서로 원자적으로 선점한 실행만 부른다:
 *
 *   1. 기존 'pending' 행이 있으면 `status='pending'` 조건까지 건 DELETE 로
 *      지운다 — 두 실행이 동시에 시도하면 한쪽만 지우고, 진 쪽은 0행 삭제로
 *      감지해 스킵한다.
 *   2. 빈 자리에 'pending' placeholder 를 INSERT 로 새로 꽂는다 — 이것도
 *      두 실행이 겹치면 unique index(user_id, type, reference_id) 가 한쪽만
 *      통과시키고, 진 쪽은 insert 에러로 감지해 스킵한다.
 *   3. 이 두 단계를 통과한 실행만 sendFcm 을 호출하고, 끝나면 그 행을 결과로
 *      UPDATE 한다.
 *
 * 선점에서 진 실행은 'skipped_raced' 를 돌려준다 — 실제로 이미 다른 실행이
 * 처리 중이거나 방금 처리했으므로 다시 셀 필요가 없다(dedup_skipped 로 집계).
 */
export async function sendReminderIfClaimed(
  supabase: SupabaseClient,
  existing: { id: string; status: string } | null,
  input: ReminderAttemptInput,
): Promise<ReminderOutcome> {
  if (existing) {
    const { data: deleted, error: deleteError } = await supabase
      .from('notifications')
      .delete()
      .eq('id', existing.id)
      .eq('status', 'pending')
      .select('id');
    if (deleteError || !deleted || deleted.length === 0) return 'skipped_raced';
  }

  const { data: claimed, error: claimError } = await supabase
    .from('notifications')
    .insert({
      user_id: input.userId,
      type: input.type,
      title: input.title,
      body: input.body,
      reference_type: input.referenceType,
      reference_id: input.referenceId,
      club_id: input.clubId ?? null,
      status: 'pending',
    })
    .select('id')
    .single();
  if (claimError || !claimed) return 'skipped_raced';

  const { data: tokenRows } = await supabase
    .from('device_tokens')
    .select('token, platform, sound_enabled')
    .eq('user_id', input.userId)
    .eq('enabled', true);
  const targets = ((tokenRows ?? []) as DeviceTokenRow[]).map((row) => ({
    token: row.token,
    soundEnabled: row.sound_enabled,
  }));

  const result = await sendFcm(targets, {
    title: input.title,
    body: input.body,
    type: input.type,
    referenceType: input.referenceType,
    referenceId: input.referenceId,
    clubId: input.clubId,
  });

  await supabase
    .from('notifications')
    .update({
      status: result.status === 'skipped' ? 'pending' : result.status,
      error: result.error,
      sent_at: result.status === 'sent' ? new Date().toISOString() : null,
    })
    .eq('id', (claimed as { id: string }).id);

  return result.status === 'sent' ? 'sent' : 'failed';
}
