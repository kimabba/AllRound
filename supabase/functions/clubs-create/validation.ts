export type ValidationResult<T> =
  | { ok: true; value: T }
  | { ok: false; message: string };

const meetingDays = new Set(['월', '화', '수', '목', '금', '토', '일']);
const genderPreferences = new Set(['mixed', 'male', 'female']);
const feeTypes = new Set(['monthly', 'per_event']);
const maxMonthlyFee = 1_000_000;
const minDescriptionLength = 30;
const maxDescriptionLength = 2_000;
const clubCardColors = new Set([
  '#18376D',
  '#3156D8',
  '#176B63',
  '#6941C6',
  '#C2413B',
  '#A15C08',
]);

export function parseClubCardColor(
  value: unknown,
): ValidationResult<string> {
  if (value === undefined || value === null || value === '') {
    return { ok: true, value: '#3156D8' };
  }
  if (typeof value !== 'string') {
    return { ok: false, message: 'card_color is invalid' };
  }
  const normalized = value.toUpperCase();
  return clubCardColors.has(normalized)
    ? { ok: true, value: normalized }
    : { ok: false, message: 'card_color is invalid' };
}

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

export function parseFeeType(value: unknown): ValidationResult<string> {
  if (value === undefined || value === null || value === '') {
    return { ok: true, value: 'monthly' };
  }
  if (typeof value !== 'string' || !feeTypes.has(value)) {
    return { ok: false, message: 'fee_type must be monthly or per_event' };
  }
  return { ok: true, value };
}

export function parseClubDescription(
  value: unknown,
): ValidationResult<string> {
  if (typeof value !== 'string') {
    return { ok: false, message: 'description is required' };
  }
  const description = value.trim();
  if (
    description.length < minDescriptionLength ||
    description.length > maxDescriptionLength
  ) {
    return {
      ok: false,
      message: 'description must be between 30 and 2000 characters',
    };
  }
  return { ok: true, value: description };
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

export function parseWebsite(
  value: unknown,
): ValidationResult<string | null> {
  if (value === undefined || value === null || value === '') {
    return { ok: true, value: null };
  }
  if (typeof value !== 'string') {
    return { ok: false, message: 'website must be a valid HTTP(S) URL' };
  }

  const website = value.trim();
  if (website === '') return { ok: true, value: null };
  const normalized = website.includes('://') ? website : `https://${website}`;
  try {
    const url = new URL(normalized);
    if (
      (url.protocol !== 'http:' && url.protocol !== 'https:') ||
      url.hostname === ''
    ) {
      return { ok: false, message: 'website must be a valid HTTP(S) URL' };
    }
  } catch {
    return { ok: false, message: 'website must be a valid HTTP(S) URL' };
  }
  return { ok: true, value: normalized };
}
