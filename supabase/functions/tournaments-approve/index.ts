import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';

/**
 * POST /tournaments-approve
 * Body: { id: uuid, action: 'approve'|'reject', reason?: string }
 *
 * 관리자만 호출 가능.
 *   - approve → status='published', rejection_reason=null
 *   - reject  → status='rejected', rejection_reason=body.reason (필수)
 *
 * 'rejected' 는 022 마이그레이션에서 추가된 신규 enum 값.
 * 'closed' (=마감된 대회) 와 의미적으로 분리해 사용한다.
 */
Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireAdmin(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: { id?: string; action?: 'approve' | 'reject'; reason?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.id) return errorResponse('id required');
  if (body.action !== 'approve' && body.action !== 'reject') {
    return errorResponse('action must be approve or reject');
  }
  if (
    body.action === 'reject' &&
    (typeof body.reason !== 'string' || body.reason.trim().length === 0)
  ) {
    return errorResponse('rejection reason required');
  }

  const update = body.action === 'approve'
    ? {
      status: 'published' as const,
      approved_by: user.id,
      approved_at: new Date().toISOString(),
      rejection_reason: null,
    }
    : {
      status: 'rejected' as const,
      approved_by: user.id,
      approved_at: new Date().toISOString(),
      rejection_reason: (body.reason as string).trim(),
    };

  // status='draft' 가드: 이미 처리된 행 (published/rejected/closed) 은 변경 차단.
  // bulk RPC (tournaments_bulk_approve/reject) 와 상태 전이 규칙 일치 + 멱등성.
  const { data, error } = await supabase
    .from('tournaments')
    .update(update)
    .eq('id', body.id)
    .eq('status', 'draft')
    .select()
    .single();

  if (error) {
    // PGRST116 = 0 rows. status='draft' 가드 실패 또는 id 미존재.
    if (error.code === 'PGRST116') {
      return errorResponse('대상이 draft 상태가 아니거나 존재하지 않습니다', 409);
    }
    return errorResponse(error.message, 500);
  }
  return jsonResponse({ tournament: data });
}));
