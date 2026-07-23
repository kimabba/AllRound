// 전화번호 인증 — OTP 검증. 성공 시 현재 사용자에 phone_hash 기록.
// 중복번호(ALREADY_USED)는 코드 검증 성공 뒤에만 노출(enumeration 방지).

import { requireUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { hashCode, hashPhone, normalizeE164Kr } from '../_shared/phone.ts';
import { serviceClient } from '../_shared/supabase.ts';

const MAX_ATTEMPTS = 5;
const LOCK_SECONDS = 900; // 15분

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;

  let raw = '';
  let code = '';
  try {
    const body = await req.json();
    raw = typeof body?.phone === 'string' ? body.phone : '';
    code = typeof body?.code === 'string' ? body.code : '';
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  if (!/^\d{6}$/.test(code)) return errorResponse('인증번호 6자리를 입력하세요.', 400);

  let e164: string;
  try {
    e164 = normalizeE164Kr(raw);
  } catch {
    return errorResponse('유효한 휴대폰 번호를 입력하세요.', 400);
  }

  const pepper = Deno.env.get('PHONE_HASH_PEPPER');
  if (!pepper) {
    console.error('[verify-otp] PHONE_HASH_PEPPER missing');
    return errorResponse('Verification unavailable', 503);
  }

  // RPC 는 service_role 전용. 신원은 검증된 JWT 의 user.id 로 넘긴다(auth.uid 미의존).
  const { data, error } = await serviceClient().rpc('verify_phone_otp', {
    p_user_id: auth.user.id,
    p_phone_hash: await hashPhone(e164, pepper),
    p_code_hash: await hashCode(code, pepper),
    p_max_attempts: MAX_ATTEMPTS,
    p_lock_seconds: LOCK_SECONDS,
  });
  if (error) {
    console.error('[verify-otp] verify_phone_otp failed:', error.message);
    return errorResponse('Verification temporarily unavailable', 503);
  }

  const result = data as { status: string; remaining?: number };
  switch (result.status) {
    case 'OK':
      return jsonResponse({ ok: true });
    case 'INVALID':
      return errorResponse('인증번호가 일치하지 않습니다.', 400, { remaining: result.remaining });
    case 'LOCKED':
    case 'EXPIRED_OR_LOCKED':
      return errorResponse('인증 시도가 초과되었거나 만료되었습니다. 다시 발송해 주세요.', 429);
    case 'ALREADY_USED':
      return errorResponse('이미 다른 계정에서 사용 중인 번호입니다.', 409);
    default:
      return errorResponse('인증에 실패했습니다.', 400);
  }
});
