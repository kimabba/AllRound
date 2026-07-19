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
import { parseOwnedPublicObjects, publicMediaBucketIds } from '../_shared/account_deletion.ts';
import { serviceClient } from '../_shared/supabase.ts';
import type { SupabaseClient } from '@supabase/supabase-js';

async function deletePublicMedia(
  client: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data, error } = await client.rpc('public_storage_paths_owned_by', {
    p_user_id: userId,
  });
  if (error) throw new Error('Public storage inventory failed');

  const ownedObjects = parseOwnedPublicObjects(data);
  for (const bucketId of publicMediaBucketIds()) {
    const names = ownedObjects
      .filter((object) => object.bucketId === bucketId)
      .map((object) => object.objectName);
    for (let offset = 0; offset < names.length; offset += 100) {
      const { error: removeError } = await client.storage
        .from(bucketId)
        .remove(names.slice(offset, offset + 100));
      if (removeError) throw new Error('Public storage removal failed');
    }
  }
}

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
    console.error('delete_account_data failed', { code: dataErr.code });
    return errorResponse('account deletion failed', 500);
  }

  // 2) 공개 UGC 사진 삭제. 신고 증거는 private bucket에서 법적 보존 정책에
  // 따라 별도 관리하며 여기서 일괄 삭제하지 않는다.
  try {
    await deletePublicMedia(svc, user.id);
  } catch (error) {
    console.error('public storage deletion failed', {
      reason: error instanceof Error ? error.message : 'unknown',
    });
    return errorResponse('account deletion failed', 500);
  }

  // 3) auth 계정 삭제(로그인 제거)
  const { error: authErr } = await svc.auth.admin.deleteUser(user.id);
  if (authErr) {
    console.error('auth account deletion failed', { status: authErr.status });
    return errorResponse('account deletion failed', 500);
  }

  return jsonResponse({ deleted: true });
});
