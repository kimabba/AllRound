import { requireVerifiedUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { createNotification } from '../_shared/notifications.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { ugcAccessError } from '../_shared/ugc.ts';

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requiredText(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text.length > 0 && text.length <= maxLength ? text : null;
}

function optionalText(value: unknown, maxLength: number): string | null {
  if (value === null || value === undefined || value === '') return null;
  return requiredText(value, maxLength);
}

function optionalInteger(value: unknown, minimum: number): number | null {
  if (value === null || value === undefined) return null;
  return Number.isInteger(value) && Number(value) >= minimum ? Number(value) : null;
}

function repeatInterval(value: unknown): 'weekly' | 'monthly' | null {
  return value === 'weekly' || value === 'monthly' ? value : null;
}

function nextMonthlyOccurrence(base: Date, offset: number): Date {
  const year = base.getUTCFullYear();
  const month = base.getUTCMonth() + offset;
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return new Date(Date.UTC(
    year,
    month,
    Math.min(base.getUTCDate(), lastDay),
    base.getUTCHours(),
    base.getUTCMinutes(),
    base.getUTCSeconds(),
    base.getUTCMilliseconds(),
  ));
}

Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireVerifiedUser(req);
  if ('error' in auth) return auth.error;

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  if (!isRecord(rawBody)) return errorResponse('Invalid JSON object', 400);

  const action = rawBody.action === undefined ? 'create' : rawBody.action;
  if (action !== 'create' && action !== 'end' && action !== 'delete') {
    return errorResponse('Invalid action', 400);
  }
  const clubId = requiredText(rawBody.club_id, 64);
  if (clubId === null) return errorResponse('Invalid club id', 400);

  const supabase = serviceClient();
  const { data: membership, error: membershipError } = await supabase
    .from('club_members')
    .select('role, status, can_create_event')
    .eq('club_id', clubId)
    .eq('user_id', auth.user.id)
    .maybeSingle();
  if (membershipError) return errorResponse(membershipError.message, 500);
  const canManage = membership?.status === 'active' &&
    (membership.role === 'owner' || membership.role === 'manager' ||
      membership.can_create_event === true);
  if (!canManage) return errorResponse('Event manager permission required', 403);

  if (action === 'end' || action === 'delete') {
    const eventId = requiredText(rawBody.event_id, 64);
    if (eventId === null) return errorResponse('Invalid event id', 400);

    // 종료·삭제는 작성자 또는 owner/manager 만. can_create_event 는 생성 권한일
    // 뿐이라 여기서 허용하면 club_events UPDATE/DELETE RLS(작성자 또는 매니저)를
    // service_role 로 우회하게 되고, 화면(owner/manager 에게만 관리 메뉴 노출)과도
    // 어긋난다.
    const { data: targetEvent, error: targetError } = await supabase
      .from('club_events')
      .select('created_by')
      .eq('id', eventId)
      .eq('club_id', clubId)
      .maybeSingle();
    if (targetError) return errorResponse(targetError.message, 500);
    if (!targetEvent) return errorResponse('Event not found', 404);
    const isClubManager = membership?.role === 'owner' ||
      membership?.role === 'manager';
    if (!isClubManager && targetEvent.created_by !== auth.user.id) {
      return errorResponse('Event manager permission required', 403);
    }

    const { error } = action === 'delete'
      ? await supabase
        .from('club_events')
        .delete()
        .eq('id', eventId)
        .eq('club_id', clubId)
      : await supabase
        .from('club_events')
        .update({ ended_early_at: new Date().toISOString() })
        .eq('id', eventId)
        .eq('club_id', clubId);
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true });
  }

  const title = requiredText(rawBody.title, 100);
  const startsAtText = requiredText(rawBody.starts_at, 64);
  const startsAt = startsAtText === null ? null : new Date(startsAtText);
  if (
    title === null || startsAt === null ||
    Number.isNaN(startsAt.getTime()) || startsAt.getTime() <= Date.now()
  ) {
    return errorResponse('Invalid club event fields', 400);
  }

  const description = optionalText(rawBody.description, 2000);
  const locationText = optionalText(rawBody.location_text, 300);
  const fee = optionalInteger(rawBody.fee, 0);
  const capacity = optionalInteger(rawBody.capacity, 1);
  const repeat = repeatInterval(rawBody.repeat_interval);
  if (
    rawBody.repeat_interval !== null && rawBody.repeat_interval !== undefined && repeat === null
  ) {
    return errorResponse('Invalid repeat interval', 400);
  }
  // 길이 초과는 null 로 바뀌므로, 값이 들어왔는데 null 이면 조용히 버리지 말고
  // 오류로 돌려준다(입력이 사라진 채 생성 성공하는 것을 막는다).
  if (
    (rawBody.description !== null && rawBody.description !== undefined &&
      rawBody.description !== '' && description === null) ||
    (rawBody.location_text !== null && rawBody.location_text !== undefined &&
      rawBody.location_text !== '' && locationText === null)
  ) {
    return errorResponse('Invalid description or location', 400);
  }
  if (
    (rawBody.fee !== null && rawBody.fee !== undefined && fee === null) ||
    (rawBody.capacity !== null && rawBody.capacity !== undefined && capacity === null)
  ) {
    return errorResponse('Invalid fee or capacity', 400);
  }

  const accessError = await ugcAccessError(
    supabase,
    auth.user.id,
    'community_create',
  );
  if (accessError) return errorResponse(accessError, 403);

  // 정기 일정은 첫 일정을 포함해 앞으로 12회 생성한다. 각 일정은 독립적으로
  // 참석·조기 종료·삭제할 수 있고, 반복 주기는 목록의 표시 정보로 남긴다.
  const occurrenceCount = repeat === null ? 1 : 12;
  const eventRows = Array.from({ length: occurrenceCount }, (_, index) => {
    const occurrence = repeat === 'weekly'
      ? new Date(startsAt.getTime() + index * 7 * 24 * 60 * 60 * 1000)
      : repeat === 'monthly'
      ? nextMonthlyOccurrence(startsAt, index)
      : startsAt;
    return {
      club_id: clubId,
      created_by: auth.user.id,
      title,
      description,
      location_text: locationText,
      starts_at: occurrence.toISOString(),
      fee,
      capacity,
      repeat_interval: repeat,
    };
  });
  const { data: events, error: eventError } = await supabase
    .from('club_events')
    .insert(eventRows)
    .select();
  const event = events?.[0];
  if (eventError || !event) {
    return errorResponse(eventError?.message ?? 'Event creation failed', 500);
  }

  const { data: club } = await supabase
    .from('clubs')
    .select('name')
    .eq('id', clubId)
    .maybeSingle();
  const { data: memberRows } = await supabase
    .from('club_members')
    .select('user_id')
    .eq('club_id', clubId)
    .eq('status', 'active')
    .neq('user_id', auth.user.id);
  const clubName = typeof club?.name === 'string' ? club.name : '모임';
  // club_events SELECT RLS 는 차단 관계(is_user_blocked_pair)를 숨긴다.
  // 알림으로 제목을 보내면 그 차단이 무의미해지므로 수신자에서 제외한다.
  const { data: blockRows } = await supabase
    .from('user_blocks')
    .select('blocker_id, blocked_id')
    .or(`blocker_id.eq.${auth.user.id},blocked_id.eq.${auth.user.id}`);
  const blockedWithAuthor = new Set(
    (blockRows ?? []).map((row) =>
      row.blocker_id === auth.user.id ? row.blocked_id : row.blocker_id
    ),
  );
  const recipients = (memberRows ?? [])
    .map((member) => member.user_id)
    .filter((userId): userId is string => typeof userId === 'string')
    .filter((userId) => !blockedWithAuthor.has(userId));
  const results = await Promise.allSettled(
    recipients.map((userId) =>
      createNotification(supabase, {
        userId,
        type: 'club_event',
        title: `${clubName} 새 일정`,
        body: title,
        referenceType: 'club_event',
        referenceId: event.id,
        clubId,
      })
    ),
  );
  const notificationFailures = results.filter(
    (result) => result.status === 'rejected',
  ).length;

  return jsonResponse(
    {
      event,
      created_count: events?.length ?? 1,
      notified_count: recipients.length - notificationFailures,
      notification_failed_count: notificationFailures,
    },
    { status: 201 },
  );
}));
