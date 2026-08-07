function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function rejoiningUserIdsFromRows(value: unknown): Set<string> {
  const ids = new Set<string>();
  if (!Array.isArray(value)) return ids;

  for (const row of value) {
    if (!isRecord(row) || row.status !== 'left') continue;
    if (typeof row.user_id === 'string' && row.user_id.length > 0) {
      ids.add(row.user_id);
    }
  }
  return ids;
}
