// clubs-review-join: 클럽장/운영진이 가입 신청 목록 조회·승인·거절
// GET ?club_id=<uuid>
// POST { request_id, action: 'approve'|'reject', reason? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { canReviewClub, reviewJoin } from './review.ts';

function stringField(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function recordField(value: unknown): Record<string, unknown> | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'GET' && req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  const supa = serviceClient();
  const reviewerId = auth.user.id;

  if (req.method === 'GET') {
    const clubId = new URL(req.url).searchParams.get('club_id')?.trim() ?? '';
    if (!clubId) return errorResponse('club_id is required', 400);
    if (!(await canReviewClub(supa, reviewerId, clubId))) {
      return errorResponse('Forbidden: owner/manager or admin only', 403);
    }

    const { data: rawRequests, error: requestsError } = await supa
      .from('club_join_requests')
      .select('id, user_id, message, created_at')
      .eq('club_id', clubId)
      .eq('status', 'pending')
      .order('created_at');
    if (requestsError) return errorResponse('JOIN_REQUEST_LIST_FAILED', 500);

    const requests = Array.isArray(rawRequests)
      ? rawRequests.map(recordField).filter(
        (row): row is Record<string, unknown> => row !== null,
      )
      : [];
    const userIds = [
      ...new Set(
        requests.map((row) => stringField(row.user_id)).filter(
          (id): id is string => id !== null,
        ),
      ),
    ];
    const profiles = new Map<string, Record<string, unknown>>();
    if (userIds.length > 0) {
      const { data: rawProfiles, error: profilesError } = await supa
        .from('users')
        // 운영진 승인 판단에 필요한 표시 이름만. avatar/지역 등은 UI 미사용이라
        // service_role 로 조회해 내려주지 않는다(최소 노출).
        .select('id, nickname, name')
        .in('id', userIds);
      if (profilesError) return errorResponse('JOIN_REQUEST_PROFILE_FAILED', 500);
      if (Array.isArray(rawProfiles)) {
        for (const value of rawProfiles) {
          const profile = recordField(value);
          const id = stringField(profile?.id);
          if (profile && id) profiles.set(id, profile);
        }
      }
    }

    return jsonResponse({
      requests: requests.map((request) => {
        const userId = stringField(request.user_id);
        const profile = userId === null ? null : profiles.get(userId) ?? null;
        return {
          ...request,
          applicant: profile === null ? null : {
            display_name: stringField(profile.nickname) ??
              stringField(profile.name),
          },
        };
      }),
    });
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  const body = recordField(rawBody);
  if (!body) return errorResponse('Invalid JSON', 400);
  const requestId = stringField(body.request_id);
  const action = stringField(body.action);
  if (!requestId) return errorResponse('request_id is required', 400);
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be approve|reject', 400);
  }

  const result = await reviewJoin(supa, { requestId, action, reviewerId });
  if (!result.ok) return errorResponse(result.message, result.status);
  return jsonResponse({ ok: true, action: result.action });
});
