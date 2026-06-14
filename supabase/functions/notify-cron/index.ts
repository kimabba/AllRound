import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { jsonResponse, preflight } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';

/**
 * pg_cron 이 매시간 호출.
 *
 * 즐겨찾기한 대회의:
 *   - D-3 (start_date - 3일 == 오늘)
 *   - 신청 마감일 == 오늘
 * 알림을 발송한다. notifications 의 unique idx (user, reference, type) 로 중복 방지.
 *
 * FCM 발송은 FCM_SERVER_KEY 가 설정된 경우에만 수행.
 * (개발 단계에서는 환경변수 없이도 로직 검증 가능 — 실패는 status='failed' 로 기록)
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

async function sendFcm(tokens: string[], title: string, body: string): Promise<boolean> {
  const serverKey = Deno.env.get('FCM_SERVER_KEY');
  if (!serverKey || tokens.length === 0) return false;

  // Firebase Cloud Messaging Legacy HTTP API
  // 운영 시 v1 API + service account 권장. MVP 는 legacy 로 시작.
  const res = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${serverKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      registration_ids: tokens,
      notification: { title, body },
      priority: 'high',
    }),
  });
  return res.ok;
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

  // deno-lint-ignore no-explicit-any
  const tasks: NotifyTask[] = ((favorites as any[]) ?? [])
    .flatMap((f) => {
      const t = f.tournaments;
      const out: NotifyTask[] = [];
      if (t.start_date === dPlus3) {
        out.push({
          user_id: f.user_id,
          tournament_id: t.id,
          type: 'd_minus_3',
          title: t.title,
          start_date: t.start_date,
          application_deadline: t.application_deadline,
        });
      }
      if (t.application_deadline === today) {
        out.push({
          user_id: f.user_id,
          tournament_id: t.id,
          type: 'deadline',
          title: t.title,
          start_date: t.start_date,
          application_deadline: t.application_deadline,
        });
      }
      return out;
    });

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

    let ok = false;
    let errText: string | null = null;
    try {
      ok = await sendFcm(tokens, '대회 알림', message);
    } catch (e) {
      errText = (e as Error).message;
    }

    const notifTitle = task.type === 'd_minus_3' ? '대회 3일 전 알림' : '신청 마감 알림';
    await supabase.from('notifications').insert({
      user_id: task.user_id,
      type: notifType,
      title: notifTitle,
      body: message,
      reference_type: 'tournament',
      reference_id: task.tournament_id,
      status: ok ? 'sent' : 'failed',
      error: errText,
      sent_at: ok ? new Date().toISOString() : null,
    });

    if (ok) sent++;
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
