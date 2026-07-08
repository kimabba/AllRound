// clubs-create: 클럽 생성 요청 (status='pending' → 어드민 승인 대기)
// POST { sport, name, region?, address?, logo_url?, contact?, website?, description? }

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }

  const sport = body.sport as string;
  if (sport !== 'tennis' && sport !== 'futsal') {
    return errorResponse('sport must be tennis or futsal', 400);
  }
  const name = (body.name as string | undefined)?.trim();
  if (!name) return errorResponse('name is required', 400);

  const supa = serviceClient();
  const logoUrl = (body.logo_url as string | undefined)?.trim() || null;
  const insertPayload: Record<string, unknown> = {
    sport,
    name,
    region: (body.region as string | undefined)?.trim() || null,
    address: (body.address as string | undefined)?.trim() || null,
    logo_url: logoUrl,
    contact: (body.contact as string | undefined)?.trim() || null,
    website: (body.website as string | undefined)?.trim() || null,
    description: (body.description as string | undefined)?.trim() || null,
    meeting_days: Array.isArray(body.meeting_days) ? body.meeting_days : [],
    monthly_fee: typeof body.monthly_fee === 'number' ? body.monthly_fee : null,
    gender_preference: typeof body.gender_preference === 'string'
      ? body.gender_preference.trim() || null
      : null,
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
    clubErr.message.includes("'logo_url' column")
  ) {
    const { logo_url: _logoUrl, ...payloadWithoutLogo } = insertPayload;
    void _logoUrl;
    const fallback = await supa
      .from('clubs')
      .insert(payloadWithoutLogo)
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

  return jsonResponse({ club }, { status: 201 });
});
