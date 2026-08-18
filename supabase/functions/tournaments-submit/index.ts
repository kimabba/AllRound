import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { requireVerifiedUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { assertKnownOrgs, fetchActiveOrgCodes } from '../_shared/orgs.ts';
import {
  EntryFeeUnit,
  isValidEntryFeeUnit,
  isValidGrade,
  isValidRegionCode,
  RegionCode,
  resolveRegionCode,
  Sport,
  TennisOrg,
} from '../_shared/enums.ts';

/**
 * POST /tournaments-submit
 *
 * 일반 사용자가 대회를 제보. status='draft' 로 저장되며 관리자가 승인하면 published.
 *
 * Body:
 *  {
 *    sport: 'tennis' | 'futsal',
 *    title: string,
 *    organizer?: string,
 *    description?: string,
 *    start_date: 'YYYY-MM-DD',
 *    end_date?: string,
 *    application_deadline?: string,
 *    region?: string,
 *    location?: string,
 *    eligible_grades: string[],
 *    entry_fee?: number,
 *    prize?: string,
 *    format?: string,
 *    source_url?: string,
 *    poster_url?: string
 *  }
 */
interface SubmitBody {
  sport: Sport;
  title: string;
  organizer?: string;
  description?: string;
  start_date: string;
  end_date?: string;
  application_deadline?: string;
  region?: string;
  location?: string;
  eligible_grades: string[];
  entry_fee?: number;
  entry_fee_unit?: EntryFeeUnit;
  prize?: string;
  format?: string;
  source_url?: string;
  poster_url?: string;
  // Phase 2 신규
  region_code?: RegionCode;
  host_associations?: string[];
  host_orgs?: TennisOrg[];
  division_label_local?: string;
  division_kta_standard?: string;
  is_joint_event?: boolean;
}

type JsonRecord = Record<string, unknown>;

type ParseResult<T> = { value: T } | { error: string };

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function optionalString(record: JsonRecord, key: string): ParseResult<string | undefined> {
  const value = record[key];
  if (value === undefined || value === null) return { value: undefined };
  if (typeof value !== 'string') return { error: `${key} must be a string` };
  return { value };
}

function optionalBoolean(record: JsonRecord, key: string): ParseResult<boolean | undefined> {
  const value = record[key];
  if (value === undefined || value === null) return { value: undefined };
  if (typeof value !== 'boolean') return { error: `${key} must be boolean` };
  return { value };
}

function optionalNumber(record: JsonRecord, key: string): ParseResult<number | undefined> {
  const value = record[key];
  if (value === undefined || value === null) return { value: undefined };
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return { error: `${key} must be a finite number` };
  }
  return { value };
}

function stringArray(record: JsonRecord, key: string): ParseResult<string[]> {
  const value = record[key];
  if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
    return { error: `${key} must be an array of strings` };
  }
  return { value };
}

function optionalStringArray(record: JsonRecord, key: string): ParseResult<string[] | undefined> {
  const value = record[key];
  if (value === undefined || value === null) return { value: undefined };
  if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
    return { error: `${key} must be an array of strings` };
  }
  return { value };
}

function parseSubmitBody(raw: unknown): ParseResult<SubmitBody> {
  if (!isRecord(raw)) return { error: 'Invalid JSON body' };

  const sport = raw.sport;
  if (sport !== 'tennis' && sport !== 'futsal') {
    return { error: 'sport must be tennis or futsal' };
  }

  const title = optionalString(raw, 'title');
  if ('error' in title) return title;
  const startDate = optionalString(raw, 'start_date');
  if ('error' in startDate) return startDate;
  const eligibleGrades = stringArray(raw, 'eligible_grades');
  if ('error' in eligibleGrades) return eligibleGrades;

  const organizer = optionalString(raw, 'organizer');
  if ('error' in organizer) return organizer;
  const description = optionalString(raw, 'description');
  if ('error' in description) return description;
  const endDate = optionalString(raw, 'end_date');
  if ('error' in endDate) return endDate;
  const applicationDeadline = optionalString(raw, 'application_deadline');
  if ('error' in applicationDeadline) return applicationDeadline;
  const region = optionalString(raw, 'region');
  if ('error' in region) return region;
  const location = optionalString(raw, 'location');
  if ('error' in location) return location;
  const entryFee = optionalNumber(raw, 'entry_fee');
  if ('error' in entryFee) return entryFee;
  const entryFeeUnit = optionalString(raw, 'entry_fee_unit');
  if ('error' in entryFeeUnit) return entryFeeUnit;
  const prize = optionalString(raw, 'prize');
  if ('error' in prize) return prize;
  const format = optionalString(raw, 'format');
  if ('error' in format) return format;
  const sourceUrl = optionalString(raw, 'source_url');
  if ('error' in sourceUrl) return sourceUrl;
  const posterUrl = optionalString(raw, 'poster_url');
  if ('error' in posterUrl) return posterUrl;
  const regionCode = optionalString(raw, 'region_code');
  if ('error' in regionCode) return regionCode;
  const hostAssociations = optionalStringArray(raw, 'host_associations');
  if ('error' in hostAssociations) return hostAssociations;
  const hostOrgs = optionalStringArray(raw, 'host_orgs');
  if ('error' in hostOrgs) return hostOrgs;
  const divisionLabelLocal = optionalString(raw, 'division_label_local');
  if ('error' in divisionLabelLocal) return divisionLabelLocal;
  const divisionKtaStandard = optionalString(raw, 'division_kta_standard');
  if ('error' in divisionKtaStandard) return divisionKtaStandard;
  const isJointEvent = optionalBoolean(raw, 'is_joint_event');
  if ('error' in isJointEvent) return isJointEvent;

  return {
    value: {
      sport,
      title: title.value ?? '',
      organizer: organizer.value,
      description: description.value,
      start_date: startDate.value ?? '',
      end_date: endDate.value,
      application_deadline: applicationDeadline.value,
      region: region.value,
      location: location.value,
      eligible_grades: eligibleGrades.value,
      entry_fee: entryFee.value,
      entry_fee_unit: entryFeeUnit.value as EntryFeeUnit | undefined,
      prize: prize.value,
      format: format.value,
      source_url: sourceUrl.value,
      poster_url: posterUrl.value,
      // 앱은 지역을 자유 입력으로만 보내고 region_code 는 보내지 않는다. 코드가 없으면
      // 지역 필터(region_code 정확매칭)에서 영원히 빠지므로 라벨에서 유도해 채운다.
      // 크롤러는 2026-06 에 같은 처리를 했지만 제보 경로가 빠져 있었다(#32).
      region_code: resolveRegionCode(
        regionCode.value as RegionCode | undefined,
        region.value,
      ),
      host_associations: hostAssociations.value,
      host_orgs: hostOrgs.value as TennisOrg[] | undefined,
      division_label_local: divisionLabelLocal.value,
      division_kta_standard: divisionKtaStandard.value,
      is_joint_event: isJointEvent.value,
    },
  };
}

function normalizeOptionalUrl(
  value: string | undefined,
  fieldName: string,
): ParseResult<string | null> {
  if (value === undefined || value.trim().length === 0) {
    return { value: null };
  }
  const trimmed = value.trim();
  if (trimmed.length > 1000) return { error: `${fieldName} must be 1000 characters or fewer` };
  try {
    const url = new URL(trimmed);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return { error: `${fieldName} must start with http:// or https://` };
    }
  } catch {
    return { error: `${fieldName} must be a valid URL` };
  }
  return { value: trimmed };
}

// import.meta.main 가드: 테스트가 이 모듈을 import 할 때(age_gate_wiring_test.ts)
// Deno.serve 가 같이 실행되며 포트 바인딩을 시도하는 걸 막는다(embed-pending/index.ts 와 동일 패턴).
async function handler(req: Request): Promise<Response> {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireVerifiedUser(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: SubmitBody;
  try {
    const parsed = parseSubmitBody(await req.json());
    if ('error' in parsed) return errorResponse(parsed.error);
    body = parsed.value;
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.title?.trim()) return errorResponse('title required');
  if (body.title.trim().length > 200) return errorResponse('title must be 200 characters or fewer');
  if (body.description && body.description.length > 2000) {
    return errorResponse('description must be 2000 characters or fewer');
  }
  if (body.organizer && body.organizer.length > 100) {
    return errorResponse('organizer must be 100 characters or fewer');
  }
  if (!body.start_date) return errorResponse('start_date required');
  if (!Array.isArray(body.eligible_grades) || body.eligible_grades.length === 0) {
    return errorResponse('eligible_grades required (non-empty array)');
  }
  // 등급 정본은 DB public.grades — TS 사본을 보면 관리자가 추가한 등급을 여기서만 거부한다(#319).
  const { data: gradeRows, error: gradeErr } = await supabase
    .from('grades')
    .select('code')
    .eq('sport', body.sport)
    .eq('is_active', true);
  if (gradeErr) return errorResponse(`grade catalog unavailable: ${gradeErr.message}`, 503);
  const activeGrades = new Set<string>((gradeRows ?? []).map((r) => r.code as string));
  // 협회(org) 카탈로그 정본도 DB tennis_orgs(#330) — isValidGrade 의 테니스 부서 코드
  // (gj_m_gold 등) org 접두사 검증에 쓴다. futsal 은 부서 코드 개념이 없어 건너뛴다.
  let activeOrgs: ReadonlySet<string> = new Set();
  if (body.sport === 'tennis') {
    const orgResult = await fetchActiveOrgCodes(supabase);
    if ('status' in orgResult) return errorResponse(orgResult.message, orgResult.status);
    activeOrgs = orgResult.codes;
  }
  for (const g of body.eligible_grades) {
    if (isValidGrade(body.sport, g, activeGrades, activeOrgs)) continue;
    // 카탈로그가 비었으면 원인은 제보 내용이 아니라 DB 상태(정책·seed 누락)다 → 503 으로 구분한다.
    // 판정 뒤에 보는 이유: 테니스 부서 코드(gj_m_gold)는 grades 와 무관하게 통과해야 하는데,
    // 빈 목록을 먼저 막으면 그 경로까지 함께 죽는다(codex 1차).
    if (activeGrades.size === 0) {
      return errorResponse(`grade catalog empty for ${body.sport}`, 503);
    }
    return errorResponse(`Invalid grade for ${body.sport}: ${g}`);
  }

  // Phase 2 신규 필드 검증
  if (body.region_code && !isValidRegionCode(body.region_code)) {
    return errorResponse(`Invalid region_code: ${body.region_code}`);
  }
  if (body.host_orgs) {
    if (!Array.isArray(body.host_orgs)) {
      return errorResponse('host_orgs must be array');
    }
    const orgError = await assertKnownOrgs(supabase, body.host_orgs);
    if (orgError) return errorResponse(orgError.message, orgError.status);
  }
  if (body.entry_fee_unit && !isValidEntryFeeUnit(body.entry_fee_unit)) {
    return errorResponse(`Invalid entry_fee_unit: ${body.entry_fee_unit}`);
  }
  const posterUrl = normalizeOptionalUrl(body.poster_url, 'poster_url');
  if ('error' in posterUrl) return errorResponse(posterUrl.error);
  const sourceUrl = normalizeOptionalUrl(body.source_url, 'source_url');
  if ('error' in sourceUrl) return errorResponse(sourceUrl.error);

  // 1. tournaments 공통 테이블 INSERT
  const { data, error } = await supabase
    .from('tournaments')
    .insert({
      sport: body.sport,
      title: body.title.trim(),
      organizer: body.organizer ?? null,
      description: body.description ?? null,
      start_date: body.start_date,
      end_date: body.end_date ?? null,
      application_deadline: body.application_deadline ?? null,
      region: body.region ?? null,
      location: body.location ?? null,
      eligible_grades: body.eligible_grades,
      entry_fee: body.entry_fee ?? null,
      entry_fee_unit: body.entry_fee_unit ?? 'per_team',
      prize: body.prize ?? null,
      format: body.format ?? null,
      source_url: sourceUrl.value,
      poster_url: posterUrl.value,
      region_code: body.region_code ?? null,
      host_associations: body.host_associations ?? [],
      division_label_local: body.division_label_local ?? null,
      source: 'user_submission',
      status: 'draft',
      submitted_by: user.id,
    })
    .select()
    .single();

  if (error) return errorResponse(error.message, 500);

  // 2. 종목별 확장 테이블 INSERT
  // 상세 테이블 RLS 는 admin 쓰기만 허용하므로 user client 로는 위반(500 + 고아 draft).
  // 방금 생성한 본인 draft 대회(status='draft', submitted_by=user)의 상세만 service_role 로 넣는다.
  const tournamentId = data.id;
  const svc = serviceClient();

  if (body.sport === 'tennis') {
    const { error: detailErr } = await svc
      .from('tennis_tournament_details')
      .insert({
        tournament_id: tournamentId,
        host_orgs: body.host_orgs ?? [],
        division_kta_standard: body.division_kta_standard ?? null,
        is_joint_event: body.is_joint_event ?? false,
      });
    if (detailErr) {
      // 부분 실패 방지: 상세 실패 시 방금 만든 draft 대회를 되돌린다.
      await svc.from('tournaments').delete().eq('id', tournamentId);
      return errorResponse(detailErr.message, 500);
    }
  } else if (body.sport === 'futsal') {
    const { error: detailErr } = await svc
      .from('futsal_tournament_details')
      .insert({ tournament_id: tournamentId });
    if (detailErr) {
      await svc.from('tournaments').delete().eq('id', tournamentId);
      return errorResponse(detailErr.message, 500);
    }
  }

  return jsonResponse({ tournament: data }, { status: 201 });
}

if (import.meta.main) {
  Deno.serve(withCors(handler));
}
