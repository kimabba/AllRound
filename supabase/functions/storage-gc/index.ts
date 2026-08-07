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

/** 앱이 만드는 난수 파일명만 로그에 남기고, 사용자가 지은 이름은 가린다. */
function loggableName(objectName: string): string {
  const basename = objectName.split('/').pop() ?? '';
  return /^[0-9a-f]{48}\.(jpg|png)$/.test(basename) ? basename : '(비표준 이름)';
}

Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const svc = serviceClient();

  async function inventory() {
    const { data, error } = await svc.rpc('orphan_club_image_objects');
    if (error) {
      console.error('orphan inventory failed', { code: error.code });
      return null;
    }
    try {
      return parseOwnedPublicObjects(data);
    } catch (parseError) {
      console.error('orphan inventory malformed', {
        reason: parseError instanceof Error ? parseError.message : 'unknown',
      });
      return null;
    }
  }

  const first = await inventory();
  if (first === null) return errorResponse('orphan inventory failed', 500);
  if (first.length === 0) return jsonResponse({ removed: 0, by_bucket: {} });

  // 목록을 만든 뒤 삭제까지의 사이에 그 객체를 참조하는 쓰기가 끼면 살아있는 사진을
  // 지우게 된다. 파일 삭제가 DB 트랜잭션 밖(Storage API)이라 이 창을 0 으로 만들려면
  // 미디어 레지스트리 + 참조 FK + 삭제 선점 상태가 필요하다 — 이 PR 범위를 넘는다.
  // 대신 청크를 지우기 직전마다 다시 조회해 창을 한 왕복으로 좁힌다.

  const removedByBucket: Record<string, number> = {};
  let removedTotal = 0;
  for (const bucketId of publicMediaBucketIds()) {
    const planned = first
      .filter((object) => object.bucketId === bucketId)
      .map((object) => object.objectName);
    for (let offset = 0; offset < planned.length; offset += 100) {
      const latest = await inventory();
      if (latest === null) return errorResponse('orphan inventory failed', 500);
      const stillOrphan = new Set(
        latest
          .filter((object) => object.bucketId === bucketId)
          .map((object) => object.objectName),
      );
      const chunk = planned
        .slice(offset, offset + 100)
        .filter((name) => stillOrphan.has(name));
      if (chunk.length === 0) continue;

      // 되돌릴 수 없는 삭제라 지운 대상을 남긴다 — 사고가 나면 무엇이 사라졌는지
      // 알아야 한다. 다만 객체명은 사용자가 정할 수 있는 값이다(Storage INSERT 정책은
      // 소유자만 보고 이름 형식은 보지 않는다). 경로의 업로더 uuid 를 떼고, 앱이 만드는
      // 난수 파일명일 때만 그대로 남긴다.
      console.log('storage-gc removing', {
        bucketId,
        names: chunk.map(loggableName),
      });
      const { error: removeError } = await svc.storage.from(bucketId).remove(chunk);
      if (removeError) {
        console.error('orphan removal failed', { bucketId, count: chunk.length });
        return errorResponse('orphan removal failed', 500);
      }
      removedByBucket[bucketId] = (removedByBucket[bucketId] ?? 0) + chunk.length;
      removedTotal += chunk.length;
    }
  }

  console.log('storage-gc removed', removedByBucket);
  return jsonResponse({ removed: removedTotal, by_bucket: removedByBucket });
}));
