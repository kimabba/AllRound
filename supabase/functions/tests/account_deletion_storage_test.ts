import { assertEquals, assertThrows } from 'std/assert/mod.ts';
import { parseOwnedPublicObjects } from '../_shared/account_deletion.ts';

Deno.test('account deletion accepts only allowlisted public media inventory', () => {
  assertEquals(
    parseOwnedPublicObjects([
      { bucket_id: 'club-logos', object_name: 'opaque.jpg' },
      { bucket_id: 'club-posts', object_name: 'opaque.png' },
    ]),
    [
      { bucketId: 'club-logos', objectName: 'opaque.jpg' },
      { bucketId: 'club-posts', objectName: 'opaque.png' },
    ],
  );
});

Deno.test('account deletion rejects private evidence and malformed paths', () => {
  assertThrows(
    () =>
      parseOwnedPublicObjects([
        { bucket_id: 'ugc-report-evidence', object_name: 'private.jpg' },
      ]),
    TypeError,
  );
  assertThrows(
    () => parseOwnedPublicObjects([{ bucket_id: 'club-logos' }]),
    TypeError,
  );
});
