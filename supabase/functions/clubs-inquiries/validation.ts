export interface InquiryRequest {
  clubId: string | null;
  threadId: string | null;
  body: string;
}

export function ageGroupFromBirthDate(
  birthDate: string | null,
  today = new Date(),
): string | null {
  if (!birthDate) return null;
  const parts = birthDate.split('-').map(Number);
  if (parts.length !== 3 || parts.some((part) => !Number.isInteger(part))) return null;
  const [year, month, day] = parts;
  let age = today.getUTCFullYear() - year;
  const birthdayPassed = today.getUTCMonth() + 1 > month ||
    (today.getUTCMonth() + 1 === month && today.getUTCDate() >= day);
  if (!birthdayPassed) age -= 1;
  if (age < 14 || age > 120) return null;
  return `${Math.floor(age / 10) * 10}대`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function optionalId(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

export function parseInquiryRequest(
  value: unknown,
): { ok: true; value: InquiryRequest } | { ok: false; message: string } {
  if (!isRecord(value)) return { ok: false, message: 'Invalid JSON object' };

  const clubId = optionalId(value.club_id);
  const threadId = optionalId(value.thread_id);
  const body = typeof value.body === 'string' ? value.body.trim() : '';
  if ((clubId === null) === (threadId === null)) {
    return { ok: false, message: 'Provide exactly one of club_id or thread_id' };
  }
  if (body.length < 1 || body.length > 1000) {
    return { ok: false, message: 'body must be between 1 and 1000 characters' };
  }
  return { ok: true, value: { clubId, threadId, body } };
}
