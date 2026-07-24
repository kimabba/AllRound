import { requireVerifiedUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
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

Deno.serve(async (req) => {
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

  const { data: event, error: eventError } = await supabase
    .from('club_events')
    .insert({
      club_id: clubId,
      created_by: auth.user.id,
      title,
      description,
      location_text: locationText,
      starts_at: startsAt.toISOString(),
      fee,
      capacity,
    })
    .select()
    .single();
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
  const clubName = typeof club?.name === 'string' ? club.name : '클럽';
  const recipients = (memberRows ?? [])
    .map((member) => member.user_id)
    .filter((userId): userId is string => typeof userId === 'string');
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
      notified_count: recipients.length - notificationFailures,
      notification_failed_count: notificationFailures,
    },
    { status: 201 },
  );
});
