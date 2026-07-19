const publicMediaBuckets = new Set([
  'club-logos',
  'club-intro-images',
  'club-posts',
]);

export type OwnedPublicObject = {
  bucketId: string;
  objectName: string;
};

export function publicMediaBucketIds(): readonly string[] {
  return [...publicMediaBuckets];
}

export function parseOwnedPublicObjects(value: unknown): OwnedPublicObject[] {
  if (!Array.isArray(value)) {
    throw new TypeError('Invalid public storage inventory');
  }

  return value.map((row) => {
    if (row === null || typeof row !== 'object') {
      throw new TypeError('Invalid public storage inventory row');
    }
    const record = row as Record<string, unknown>;
    const bucketId = record.bucket_id;
    const objectName = record.object_name;
    if (
      typeof bucketId !== 'string' ||
      !publicMediaBuckets.has(bucketId) ||
      typeof objectName !== 'string' ||
      objectName.length === 0
    ) {
      throw new TypeError('Invalid public storage inventory row');
    }
    return { bucketId, objectName };
  });
}
