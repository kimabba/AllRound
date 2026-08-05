import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import {
  needsReminderAttempt,
  parseClubEventReminders,
  parseUserIds,
  tomorrowKstBounds,
} from '../_shared/club_event_reminders.ts';
import { jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { sendFcm } from '../_shared/fcm.ts';
import { createNotification } from '../_shared/notifications.ts';
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
  sound_enabled: boolean;
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

Deno.serve(withCors(async (req) => {
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
    // dedup: 이미 같은 (user, reference, type) 발송 기록이 있으면 skip.
    // 단 'pending'(그때 기기 토큰이 없었음)은 재시도 대상 — 이전 행을 지우고
    // 새로 기록한다(user_id, type, reference_id unique 제약 때문에 upsert 대신 delete-then-insert).
    const notifType = task.type === 'd_minus_3' ? 'tournament_d3' : 'tournament_deadline';
    const { data: existing } = await supabase
      .from('notifications')
      .select('id, status')
      .eq('user_id', task.user_id)
      .eq('reference_type', 'tournament')
      .eq('reference_id', task.tournament_id)
      .eq('type', notifType)
      .maybeSingle();

    if (!needsReminderAttempt(existing?.status)) {
      dedupSkipped++;
      continue;
    }
    if (existing) {
      await supabase.from('notifications').delete().eq('id', existing.id);
    }

    // 디바이스 토큰
    const { data: tokensRow } = await supabase
      .from('device_tokens')
      .select('token, platform, sound_enabled')
      .eq('user_id', task.user_id)
      .eq('enabled', true);

    const targets = ((tokensRow ?? []) as DeviceTokenRow[]).map((token) => ({
      token: token.token,
      soundEnabled: token.sound_enabled,
    }));

    const message = task.type === 'd_minus_3'
      ? `대회 3일 전: ${task.title} — ${task.start_date}`
      : `오늘 신청 마감: ${task.title}`;

    const result = await sendFcm(targets, {
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

  // KST 기준 내일 00:00~24:00 사이의 활성 클럽 일정.
  // 삭제된 일정은 조회되지 않고, 조기 종료 일정은 ended_early_at 필터로 제외한다.
  const tomorrow = tomorrowKstBounds(new Date());
  const { data: eventRows, error: eventError } = await supabase
    .from('club_events')
    .select('id, club_id, title, starts_at, created_by, clubs(name)')
    .is('ended_early_at', null)
    .gte('starts_at', tomorrow.start)
    .lt('starts_at', tomorrow.end);
  if (eventError) {
    return jsonResponse({ error: eventError.message }, { status: 500 });
  }

  const eventReminders = parseClubEventReminders(eventRows as unknown);

  // club_events SELECT RLS 는 차단 관계를 숨기므로, D-1 알림도 같은 기준으로
  // 수신자를 걸러야 한다(제목이 알림으로 새어 나가지 않게).
  const authorIds = [
    ...new Set(
      eventReminders
        .map((event) => event.createdBy)
        .filter((id): id is string => id !== null),
    ),
  ];
  const blockedByAuthor = new Map<string, Set<string>>();
  if (authorIds.length > 0) {
    const { data: blockRows } = await supabase
      .from('user_blocks')
      .select('blocker_id, blocked_id')
      .or(
        `blocker_id.in.(${authorIds.join(',')}),blocked_id.in.(${authorIds.join(',')})`,
      );
    for (const row of blockRows ?? []) {
      const blocker = row.blocker_id as string;
      const blocked = row.blocked_id as string;
      for (const [author, other] of [[blocker, blocked], [blocked, blocker]]) {
        if (!authorIds.includes(author)) continue;
        const set = blockedByAuthor.get(author) ?? new Set<string>();
        set.add(other);
        blockedByAuthor.set(author, set);
      }
    }
  }

  for (const event of eventReminders) {
    const blockedForEvent = event.createdBy === null
      ? new Set<string>()
      : blockedByAuthor.get(event.createdBy) ?? new Set<string>();
    const { data: members, error: membersError } = await supabase
      .from('club_members')
      .select('user_id')
      .eq('club_id', event.clubId)
      .eq('status', 'active');
    if (membersError) {
      failed++;
      continue;
    }
    for (const userId of parseUserIds(members as unknown)) {
      if (blockedForEvent.has(userId)) continue;
      const { data: existing } = await supabase
        .from('notifications')
        .select('id, status')
        .eq('user_id', userId)
        .eq('type', 'club_event_reminder')
        .eq('reference_id', event.id)
        .maybeSingle();
      if (!needsReminderAttempt(existing?.status)) {
        dedupSkipped++;
        continue;
      }
      if (existing) {
        await supabase.from('notifications').delete().eq('id', existing.id);
      }
      try {
        await createNotification(supabase, {
          userId,
          type: 'club_event_reminder',
          title: `${event.clubName} 일정 하루 전`,
          body: event.title,
          referenceType: 'club_event',
          referenceId: event.id,
          clubId: event.clubId,
        });
        sent++;
      } catch {
        failed++;
      }
    }
  }

  return jsonResponse({
    today,
    candidate_count: tasks.length + eventReminders.length,
    club_event_candidate_count: eventReminders.length,
    sent,
    dedup_skipped: dedupSkipped,
    failed,
  });
}));
