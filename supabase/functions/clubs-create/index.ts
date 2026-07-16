// clubs-create: 클럽 생성 요청 (status='pending' → 어드민 승인 대기)
// POST { sport, name, region?, address?, logo_url?, intro_image_urls?, contact?, website?, description? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { ugcAccessError } from '../_shared/ugc.ts';
import { notifyAdminsOfPendingClub } from './notifications.ts';
import {
  parseGenderPreference,
  parseMeetingDays,
  parseMonthlyFee,
  parseWebsite,
} from './validation.ts';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function optionalText(value: unknown): string | null {
  return typeof value === 'string' ? value.trim() || null : null;
}

function optionalUrl(value: unknown): string | null {
  const text = optionalText(value);
  if (text === null) return null;
  try {
    const url = new URL(text);
    return url.protocol === 'http:' || url.protocol === 'https:' ? text : null;
  } catch {
    return null;
  }
}

function optionalUrlArray(value: unknown, maxItems: number): string[] {
  if (!Array.isArray(value)) return [];
  const urls: string[] = [];
  for (const item of value) {
    const url = optionalUrl(item);
    if (url !== null) urls.push(url);
    if (urls.length >= maxItems) break;
  }
  return urls;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }
  if (!isRecord(rawBody)) return errorResponse('Invalid JSON object', 400);
  const body = rawBody;

  const sport = body.sport;
  if (sport !== 'tennis' && sport !== 'futsal') {
    return errorResponse('sport must be tennis or futsal', 400);
  }
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (!name) return errorResponse('name is required', 400);

  const parsedMeetingDays = parseMeetingDays(body.meeting_days);
  if (!parsedMeetingDays.ok) {
    return errorResponse(parsedMeetingDays.message, 400);
  }
  const parsedMonthlyFee = parseMonthlyFee(body.monthly_fee);
  if (!parsedMonthlyFee.ok) {
    return errorResponse(parsedMonthlyFee.message, 400);
  }
  const parsedGenderPreference = parseGenderPreference(
    body.gender_preference,
  );
  if (!parsedGenderPreference.ok) {
    return errorResponse(parsedGenderPreference.message, 400);
  }
  const parsedWebsite = parseWebsite(body.website);
  if (!parsedWebsite.ok) {
    return errorResponse(parsedWebsite.message, 400);
  }

  const supa = serviceClient();
  const accessError = await ugcAccessError(
    supa,
    auth.user.id,
    'community_create',
  );
  if (accessError) return errorResponse(accessError, 403);
  const logoUrl = optionalUrl(body.logo_url);
  const introImageUrls = optionalUrlArray(body.intro_image_urls, 5);
  const insertPayload: Record<string, unknown> = {
    sport,
    name,
    region: optionalText(body.region),
    address: optionalText(body.address),
    logo_url: logoUrl,
    intro_image_urls: introImageUrls,
    contact: optionalText(body.contact),
    website: parsedWebsite.value,
    description: optionalText(body.description),
    meeting_days: parsedMeetingDays.value,
    monthly_fee: parsedMonthlyFee.value,
    gender_preference: parsedGenderPreference.value,
    status: 'pending',
    created_by: auth.user.id,
  };

  // 클럽 생성 (status='pending')
  let { data: club, error: clubErr } = await supa
    .from('clubs')
    .insert(insertPayload)
    .select()
    .single();

  if (
    clubErr &&
    (clubErr.message.includes("'logo_url' column") ||
      clubErr.message.includes("'intro_image_urls' column"))
  ) {
    const {
      logo_url: _logoUrl,
      intro_image_urls: _introImageUrls,
      ...fallbackPayload
    } = insertPayload;
    void _logoUrl;
    void _introImageUrls;
    const fallback = await supa
      .from('clubs')
      .insert(fallbackPayload)
      .select()
      .single();
    club = fallback.data;
    clubErr = fallback.error;
  }

  if (clubErr) return errorResponse(clubErr.message, 500);

  // 생성자를 owner로 자동 등록.
  // 실패 시 방금 만든 클럽을 보상 삭제 → owner 없는 고아 클럽(부분성공) 방지.
  const { error: ownerErr } = await supa.from('club_members').insert({
    club_id: club!.id,
    user_id: auth.user.id,
    role: 'owner',
    status: 'active',
  });
  if (ownerErr) {
    await supa.from('clubs').delete().eq('id', club!.id);
    return errorResponse('owner 등록 실패: ' + ownerErr.message, 500);
  }

  // 클럽 생성 자체는 성공했으므로, 관리자 알림 실패가 응답을 실패로
  // 바꾸지 않게 한다. 실패는 로그로 남겨 운영에서 확인한다.
  const clubId = typeof club?.id === 'string' ? club.id : '';
  if (clubId.length > 0) {
    try {
      await notifyAdminsOfPendingClub(supa, { clubId, clubName: name });
    } catch (error) {
      console.error(
        'Failed to create club approval notifications:',
        error instanceof Error ? error.message : 'Unknown error',
      );
    }
  }

  return jsonResponse({ club }, { status: 201 });
});
