import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { jsonResponse, preflight } from '../_shared/cors.ts';
import { sendFcm } from '../_shared/fcm.ts';
import { serviceClient } from '../_shared/supabase.ts';

/**
 * pg_cron 이 매시간 호출.
 *
 * 즐겨찾기한 대회의:
 *   - D-3 (start_date - 3일 == 오늘)
 *   - 신청 마감일 == 오늘
 * 알림을 발송한다. notifications 의 unique idx (user, reference, type) 로 중복 방지.
 *
 * FCM HTTP v1 발송은 FIREBASE_SERVICE_ACCOUNT_JSON secret 을 사용한다.
 */

interface NotifyTask {
  user_id: string;
  tournament_id: string;
  type: 'd_minus_3' | 'deadline';
  title: string;
  start_date: string;
  application_deadline: string | null;
}

interface DeviceTokenRow {
  token: string;
  platform: 'ios' | 'android' | 'web';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function parseTasks(rows: unknown, today: string, dPlus3: string): NotifyTask[] {
  if (!Array.isArray(rows)) return [];
  const tasks: NotifyTask[] = [];
  for (const row of rows) {
    if (!isRecord(row) || typeof row['user_id'] !== 'string') continue;
    const tournament = row['tournaments'];
    if (!isRecord(tournament)) continue;
    const id = tournament['id'];
    const title = tournament['title'];
    const startDate = tournament['start_date'];
    const deadline = tournament['application_deadline'];
    if (
      typeof id !== 'string' || typeof title !== 'string' || typeof startDate !== 'string' ||
      (deadline !== null && typeof deadline !== 'string')
    ) continue;
    if (startDate === dPlus3) {
      tasks.push({
        user_id: row['user_id'],
        tournament_id: id,
        type: 'd_minus_3',
        title,
        start_date: startDate,
        application_deadline: deadline,
      });
    }
    if (deadline === today) {
      tasks.push({
        user_id: row['user_id'],
        tournament_id: id,
        type: 'deadline',
        title,
        start_date: startDate,
        application_deadline: deadline,
      });
    }
  }
  return tasks;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const supabase = serviceClient();

  // KST(UTC+9) 기준 날짜 — DB의 date 컬럼이 한국 날짜로 저장되므로 맞춰야 함
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const today = kstNow.toISOString().slice(0, 10);
  const dPlus3 = new Date(kstNow.getTime() + 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  // 즐겨찾기 + 대회 정보 조인
  const { data: favorites, error } = await supabase
    .from('tournament_favorites')
    .select(
      'user_id, tournament_id, tournaments!inner(id, title, start_date, application_deadline, status)',
    )
    .eq('tournaments.status', 'published');

  if (error) return jsonResponse({ error: error.message }, { status: 500 });

  const tasks = parseTasks(favorites as unknown, today, dPlus3);

  let sent = 0, dedupSkipped = 0, failed = 0;

  for (const task of tasks) {
    // dedup: 이미 같은 (user, reference, type) 발송 기록이 있으면 skip
    const notifType = task.type === 'd_minus_3' ? 'tournament_d3' : 'tournament_deadline';
    const { data: existing } = await supabase
      .from('notifications')
      .select('id')
      .eq('user_id', task.user_id)
      .eq('reference_type', 'tournament')
      .eq('reference_id', task.tournament_id)
      .eq('type', notifType)
      .maybeSingle();

    if (existing) {
      dedupSkipped++;
      continue;
    }

    // 디바이스 토큰
    const { data: tokensRow } = await supabase
      .from('device_tokens')
      .select('token, platform')
      .eq('user_id', task.user_id)
      .eq('enabled', true);

    const tokens = ((tokensRow ?? []) as DeviceTokenRow[]).map((t) => t.token);

    const message = task.type === 'd_minus_3'
      ? `대회 3일 전: ${task.title} — ${task.start_date}`
      : `오늘 신청 마감: ${task.title}`;

    const result = await sendFcm(tokens, {
      title: '대회 알림',
      body: message,
      type: notifType,
      referenceType: 'tournament',
      referenceId: task.tournament_id,
    });

    const notifTitle = task.type === 'd_minus_3' ? '대회 3일 전 알림' : '신청 마감 알림';
    await supabase.from('notifications').insert({
      user_id: task.user_id,
      type: notifType,
      title: notifTitle,
      body: message,
      reference_type: 'tournament',
      reference_id: task.tournament_id,
      status: result.status === 'skipped' ? 'pending' : result.status,
      error: result.error,
      sent_at: result.status === 'sent' ? new Date().toISOString() : null,
    });

    if (result.status === 'sent') sent++;
    else failed++;
  }

  return jsonResponse({
    today,
    candidate_count: tasks.length,
    sent,
    dedup_skipped: dedupSkipped,
    failed,
  });
});
