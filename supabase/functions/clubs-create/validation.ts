export type ValidationResult<T> =
  | { ok: true; value: T }
  | { ok: false; message: string };

const meetingDays = new Set(['월', '화', '수', '목', '금', '토', '일']);
const genderPreferences = new Set(['mixed', 'male', 'female']);
const maxMonthlyFee = 1_000_000;

export function parseMeetingDays(
  value: unknown,
): ValidationResult<string[]> {
  if (value === undefined || value === null) return { ok: true, value: [] };
  if (!Array.isArray(value)) {
    return { ok: false, message: 'meeting_days must be an array' };
  }

  const unique = new Set<string>();
  for (const item of value) {
    if (typeof item !== 'string' || !meetingDays.has(item)) {
      return { ok: false, message: 'meeting_days contains an invalid value' };
    }
    unique.add(item);
  }
  return { ok: true, value: [...unique] };
}

export function parseMonthlyFee(
  value: unknown,
): ValidationResult<number | null> {
  if (value === undefined || value === null) return { ok: true, value: null };
  if (
    typeof value !== 'number' ||
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > maxMonthlyFee
  ) {
    return {
      ok: false,
      message: 'monthly_fee must be an integer between 0 and 1000000 or null',
    };
  }
  return { ok: true, value };
}

export function parseGenderPreference(
  value: unknown,
): ValidationResult<string | null> {
  if (value === undefined || value === null || value === '') {
    return { ok: true, value: null };
  }
  if (typeof value !== 'string' || !genderPreferences.has(value)) {
    return {
      ok: false,
      message: 'gender_preference must be mixed, male, female, or null',
    };
  }
  return { ok: true, value };
}
