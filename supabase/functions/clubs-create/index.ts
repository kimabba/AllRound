// clubs-create: 클럽 생성 요청 (status='pending' → 어드민 승인 대기)
// POST { sport, name, region?, address?, contact?, website?, description? }

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

  // 클럽 생성 (status='pending')
  const { data: club, error: clubErr } = await supa
    .from('clubs')
    .insert({
      sport,
      name,
      region: (body.region as string | undefined)?.trim() || null,
      address: (body.address as string | undefined)?.trim() || null,
      contact: (body.contact as string | undefined)?.trim() || null,
      website: (body.website as string | undefined)?.trim() || null,
      description: (body.description as string | undefined)?.trim() || null,
      status: 'pending',
      created_by: auth.user.id,
    })
    .select()
    .single();

  if (clubErr) return errorResponse(clubErr.message, 500);

  // 생성자를 owner로 자동 등록
  await supa.from('club_members').insert({
    club_id: club!.id,
    user_id: auth.user.id,
    role: 'owner',
    status: 'active',
  });

  return jsonResponse({ club }, 201);
});
