import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import {
  EntryFeeUnit,
  isValidEntryFeeUnit,
  isValidGrade,
  isValidRegionCode,
  isValidTennisOrg,
  RegionCode,
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
 *    source_url?: string
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
  // Phase 2 신규
  region_code?: RegionCode;
  host_associations?: string[];
  host_orgs?: TennisOrg[];
  division_label_local?: string;
  division_kta_standard?: string;
  is_joint_event?: boolean;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: SubmitBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.sport || (body.sport !== 'tennis' && body.sport !== 'futsal')) {
    return errorResponse('sport must be tennis or futsal');
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
  for (const g of body.eligible_grades) {
    if (!isValidGrade(body.sport, g)) {
      return errorResponse(`Invalid grade for ${body.sport}: ${g}`);
    }
  }

  // Phase 2 신규 필드 검증
  if (body.region_code && !isValidRegionCode(body.region_code)) {
    return errorResponse(`Invalid region_code: ${body.region_code}`);
  }
  if (body.host_orgs) {
    if (!Array.isArray(body.host_orgs)) {
      return errorResponse('host_orgs must be array');
    }
    for (const o of body.host_orgs) {
      if (!isValidTennisOrg(o)) {
        return errorResponse(`Invalid tennis_org: ${o}`);
      }
    }
  }
  if (body.entry_fee_unit && !isValidEntryFeeUnit(body.entry_fee_unit)) {
    return errorResponse(`Invalid entry_fee_unit: ${body.entry_fee_unit}`);
  }

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
      source_url: body.source_url ?? null,
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
  const tournamentId = data.id;

  if (body.sport === 'tennis') {
    const { error: detailErr } = await supabase
      .from('tennis_tournament_details')
      .insert({
        tournament_id: tournamentId,
        host_orgs: body.host_orgs ?? [],
        division_kta_standard: body.division_kta_standard ?? null,
        is_joint_event: body.is_joint_event ?? false,
      });
    if (detailErr) return errorResponse(detailErr.message, 500);
  } else if (body.sport === 'futsal') {
    const { error: detailErr } = await supabase
      .from('futsal_tournament_details')
      .insert({ tournament_id: tournamentId });
    if (detailErr) return errorResponse(detailErr.message, 500);
  }

  return jsonResponse({ tournament: data }, { status: 201 });
});
