/**
 * POST /storage-gc
 *
 * 어느 클럽 사진에도 걸려 있지 않은 Storage 파일을 지운다. pg_cron 이 하루 한 번 호출.
 *
 * 앱은 게시글 삭제·사진 교체 때 Storage 파일을 지우지 않는다(운영자가 남의 글을 지우면
 * Storage delete 정책에 막히고, 앱이 도중에 꺼져도 남는다). 참조가 끊긴 파일을 여기서
 * 한 번에 걷어낸다.
 *
 * 대상 판정은 orphan_club_image_objects RPC 가 한다 — 기본 24시간이 지났고, 클럽 로고·
 * 소개 사진·게시글 사진·신고 스냅샷 어디에서도 참조하지 않는 객체.
 *
 * 되돌릴 수 없는 삭제이므로 실패는 조용히 넘기지 않고 500 으로 세운다.
 */
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { parseOwnedPublicObjects, publicMediaBucketIds } from '../_shared/account_deletion.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const svc = serviceClient();
  const { data, error } = await svc.rpc('orphan_club_image_objects');
  if (error) {
    console.error('orphan inventory failed', { code: error.code });
    return errorResponse('orphan inventory failed', 500);
  }

  let orphans;
  try {
    orphans = parseOwnedPublicObjects(data);
  } catch (parseError) {
    console.error('orphan inventory malformed', {
      reason: parseError instanceof Error ? parseError.message : 'unknown',
    });
    return errorResponse('orphan inventory failed', 500);
  }

  const removedByBucket: Record<string, number> = {};
  for (const bucketId of publicMediaBucketIds()) {
    const names = orphans
      .filter((object) => object.bucketId === bucketId)
      .map((object) => object.objectName);
    for (let offset = 0; offset < names.length; offset += 100) {
      const chunk = names.slice(offset, offset + 100);
      const { error: removeError } = await svc.storage.from(bucketId).remove(chunk);
      if (removeError) {
        console.error('orphan removal failed', { bucketId, count: chunk.length });
        return errorResponse('orphan removal failed', 500);
      }
      removedByBucket[bucketId] = (removedByBucket[bucketId] ?? 0) + chunk.length;
    }
  }

  console.log('storage-gc removed', removedByBucket);
  return jsonResponse({ removed: orphans.length, by_bucket: removedByBucket });
}));
