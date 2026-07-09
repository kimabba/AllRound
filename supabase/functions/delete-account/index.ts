/**
 * POST /delete-account
 *
 * 로그인한 사용자가 자기 계정을 탈퇴(삭제)한다. 스토어 제출 필수 요건(JY-112).
 *
 * 처리(익명화 정책):
 *  1. delete_account_data(uid) RPC — 개인 데이터 삭제 + 작성 콘텐츠 익명화(원자적).
 *  2. auth.admin.deleteUser(uid) — 로그인 계정 삭제.
 *
 * 본인 JWT 로만 호출 가능(requireUser). uid 는 검증된 토큰에서만 취하므로
 * 타인 계정을 지울 수 없다.
 */
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;
  const { user } = auth;

  const svc = serviceClient();

  // 1) 앱 데이터 삭제 + 작성 콘텐츠 익명화 (원자적 RPC)
  const { error: dataErr } = await svc.rpc('delete_account_data', {
    p_user_id: user.id,
  });
  if (dataErr) {
    return errorResponse(`account data deletion failed: ${dataErr.message}`, 500);
  }

  // 2) auth 계정 삭제(로그인 제거)
  const { error: authErr } = await svc.auth.admin.deleteUser(user.id);
  if (authErr) {
    return errorResponse(`auth account deletion failed: ${authErr.message}`, 500);
  }

  return jsonResponse({ deleted: true });
});
