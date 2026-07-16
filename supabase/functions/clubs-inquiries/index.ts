import type { SupabaseClient } from '@supabase/supabase-js';

import { requireUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { createNotification } from '../_shared/notifications.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { ugcAccessError } from '../_shared/ugc.ts';
import { parseInquiryRequest } from './validation.ts';

interface InquiryThreadRow {
  id: string;
  club_id: string;
  requester_id: string;
}

interface ClubRow {
  id: string;
  name: string;
  status: string;
  created_by: string | null;
}

function stringField(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function threadFrom(value: unknown): InquiryThreadRow | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  const id = stringField(row.id);
  const clubId = stringField(row.club_id);
  const requesterId = stringField(row.requester_id);
  return id && clubId && requesterId ? { id, club_id: clubId, requester_id: requesterId } : null;
}

function clubFrom(value: unknown): ClubRow | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  const id = stringField(row.id);
  const name = stringField(row.name);
  const status = stringField(row.status);
  if (!id || !name || !status) return null;
  return { id, name, status, created_by: stringField(row.created_by) };
}

async function isBlockedPair(
  supabase: SupabaseClient,
  firstUserId: string,
  secondUserId: string,
): Promise<boolean> {
  const { data } = await supabase
    .from('user_blocks')
    .select('id')
    .in('blocker_id', [firstUserId, secondUserId])
    .in('blocked_user_id', [firstUserId, secondUserId])
    .limit(1);
  return Array.isArray(data) && data.length > 0;
}

async function activeOperatorIds(
  supabase: SupabaseClient,
  clubId: string,
): Promise<string[]> {
  const { data } = await supabase
    .from('club_members')
    .select('user_id')
    .eq('club_id', clubId)
    .eq('status', 'active')
    .in('role', ['owner', 'manager']);
  if (!Array.isArray(data)) return [];
  return [
    ...new Set(
      data.map((row) => stringField(row.user_id)).filter((id): id is string => id !== null),
    ),
  ];
}

async function canOperateClub(
  supabase: SupabaseClient,
  userId: string,
  clubId: string,
  isAdmin: boolean,
): Promise<boolean> {
  if (isAdmin) return true;
  const { data } = await supabase
    .from('club_members')
    .select('id')
    .eq('club_id', clubId)
    .eq('user_id', userId)
    .eq('status', 'active')
    .in('role', ['owner', 'manager'])
    .maybeSingle();
  return data !== null;
}

async function requesterLabel(
  supabase: SupabaseClient,
  requesterId: string,
): Promise<string> {
  const { data } = await supabase
    .from('users')
    .select('nickname')
    .eq('id', requesterId)
    .maybeSingle();
  return stringField(data?.nickname)?.trim() || `문의자 ${requesterId.slice(0, 8)}`;
}

async function notifyMessage(
  supabase: SupabaseClient,
  input: {
    senderId: string;
    requesterId: string;
    operatorIds: string[];
    club: ClubRow;
    threadId: string;
    messageId: string;
  },
): Promise<void> {
  const senderIsRequester = input.senderId === input.requesterId;
  const candidates = senderIsRequester ? input.operatorIds : [input.requesterId];
  const recipientIds: string[] = [];
  for (const recipientId of candidates) {
    if (recipientId === input.senderId) continue;
    if (!(await isBlockedPair(supabase, input.senderId, recipientId))) {
      recipientIds.push(recipientId);
    }
  }

  const label = senderIsRequester ? await requesterLabel(supabase, input.requesterId) : null;
  const results = await Promise.allSettled(
    recipientIds.map((recipientId) =>
      createNotification(supabase, {
        userId: recipientId,
        type: senderIsRequester ? 'club_inquiry_received' : 'club_inquiry_reply',
        title: senderIsRequester ? '새 클럽 문의' : `${input.club.name} 문의 답변`,
        body: senderIsRequester
          ? `${label}님이 ${input.club.name}에 문의했습니다.`
          : '운영진의 새 답변이 도착했습니다.',
        referenceType: `club_inquiry:${input.threadId}`,
        referenceId: input.messageId,
        clubId: input.club.id,
      })
    ),
  );
  const failed = results.filter((result) => result.status === 'rejected').length;
  if (failed > 0) throw new Error(`Failed to create ${failed} inquiry notifications`);
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  const parsed = parseInquiryRequest(rawBody);
  if (!parsed.ok) return errorResponse(parsed.message, 400);

  const supabase = serviceClient();
  const accessError = await ugcAccessError(
    supabase,
    auth.user.id,
    'community_create',
  );
  if (accessError) return errorResponse(accessError, 403);

  let thread: InquiryThreadRow | null = null;
  let club: ClubRow | null = null;

  if (parsed.value.clubId !== null) {
    const { data: clubData, error: clubError } = await supabase
      .from('clubs')
      .select('id, name, status, created_by')
      .eq('id', parsed.value.clubId)
      .maybeSingle();
    club = clubFrom(clubData);
    if (clubError || !club || club.status !== 'approved') {
      return errorResponse('CLUB_NOT_AVAILABLE', 404);
    }

    const { data: membership } = await supabase
      .from('club_members')
      .select('id')
      .eq('club_id', club.id)
      .eq('user_id', auth.user.id)
      .eq('status', 'active')
      .maybeSingle();
    if (membership) return errorResponse('ALREADY_MEMBER', 409);
    const { data: threadData, error: threadError } = await supabase
      .from('club_inquiry_threads')
      .upsert(
        {
          club_id: club.id,
          requester_id: auth.user.id,
          status: 'open',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'club_id,requester_id' },
      )
      .select('id, club_id, requester_id')
      .single();
    thread = threadFrom(threadData);
    if (threadError || !thread) return errorResponse('INQUIRY_THREAD_FAILED', 500);
  } else {
    const { data: threadData, error: threadError } = await supabase
      .from('club_inquiry_threads')
      .select('id, club_id, requester_id')
      .eq('id', parsed.value.threadId!)
      .maybeSingle();
    thread = threadFrom(threadData);
    if (threadError || !thread) return errorResponse('INQUIRY_NOT_FOUND', 404);

    const requester = auth.user.id === thread.requester_id;
    const operator = await canOperateClub(
      supabase,
      auth.user.id,
      thread.club_id,
      auth.user.isAdmin,
    );
    if (!requester && !operator) return errorResponse('FORBIDDEN', 403);
    if (
      !requester &&
      await isBlockedPair(supabase, auth.user.id, thread.requester_id)
    ) {
      return errorResponse('USER_BLOCKED', 403);
    }

    const { data: clubData } = await supabase
      .from('clubs')
      .select('id, name, status, created_by')
      .eq('id', thread.club_id)
      .maybeSingle();
    club = clubFrom(clubData);
    if (!club) return errorResponse('CLUB_NOT_AVAILABLE', 404);
  }

  let operatorIds = await activeOperatorIds(supabase, thread.club_id);
  if (auth.user.id === thread.requester_id) {
    const unblockedOperatorIds: string[] = [];
    for (const operatorId of operatorIds) {
      if (!(await isBlockedPair(supabase, auth.user.id, operatorId))) {
        unblockedOperatorIds.push(operatorId);
      }
    }
    if (unblockedOperatorIds.length === 0) {
      return errorResponse(
        operatorIds.length === 0 ? 'NO_CLUB_OPERATOR' : 'USER_BLOCKED',
        403,
      );
    }
    operatorIds = unblockedOperatorIds;
  }

  const { data: messageData, error: messageError } = await supabase
    .from('club_inquiry_messages')
    .insert({
      thread_id: thread.id,
      sender_id: auth.user.id,
      body: parsed.value.body,
    })
    .select('id')
    .single();
  const messageId = stringField(messageData?.id);
  if (messageError || !messageId) {
    const message = messageError?.message.includes('UGC_')
      ? messageError.message
      : 'INQUIRY_MESSAGE_FAILED';
    return errorResponse(message, 400);
  }

  const now = new Date().toISOString();
  await supabase
    .from('club_inquiry_threads')
    .update({ status: 'open', last_message_at: now, updated_at: now })
    .eq('id', thread.id);

  try {
    await notifyMessage(supabase, {
      senderId: auth.user.id,
      requesterId: thread.requester_id,
      operatorIds,
      club,
      threadId: thread.id,
      messageId,
    });
  } catch (error) {
    console.error(
      'Failed to create inquiry notification:',
      error instanceof Error ? error.message : 'Unknown error',
    );
  }

  return jsonResponse({ thread_id: thread.id, message_id: messageId }, { status: 201 });
});
