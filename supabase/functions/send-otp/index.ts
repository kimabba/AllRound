// 전화번호 인증 — OTP 발송. 인증된(온보딩) 사용자만 호출 가능.
// rate limit 은 fail-closed: RPC 에러 시 발송하지 않는다(SMS 비용 방어).

import { requireVerifiedUser } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import {
  generateOtp,
  hashCode,
  hashPhone,
  normalizeE164Kr,
  stringFieldOf,
  toDomesticKr,
} from '../_shared/phone.ts';
import { sendSms, sensConfigFromEnv } from '../_shared/sens.ts';
import { serviceClient } from '../_shared/supabase.ts';

const TTL_SECONDS = 180; // OTP 유효 3분
const COOLDOWN_SECONDS = 60; // 재발송 쿨다운
const HOURLY_CAP = 5; // 번호당 시간당 발송
const USER_DAILY_CAP = Number(Deno.env.get('OTP_USER_DAILY_CAP') ?? '5'); // 계정당 일일
// 글로벌 일일 상한 = 금전 서킷브레이커. 예상량 x5 수준으로 env 조정.
const DAILY_GLOBAL_CAP = Number(Deno.env.get('OTP_DAILY_GLOBAL_CAP') ?? '2000');

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireVerifiedUser(req);
  if ('error' in auth) return auth.error;

  let raw = '';
  try {
    const body: unknown = await req.json();
    raw = stringFieldOf(body, 'phone');
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  let e164: string;
  try {
    e164 = normalizeE164Kr(raw);
  } catch {
    return errorResponse('유효한 휴대폰 번호를 입력하세요.', 400);
  }

  const pepper = Deno.env.get('PHONE_HASH_PEPPER');
  if (!pepper) {
    console.error('[send-otp] PHONE_HASH_PEPPER missing');
    return errorResponse('Verification unavailable', 503);
  }

  const code = generateOtp();
  const phoneHash = await hashPhone(e164, pepper);
  const codeHash = await hashCode(code, pepper);

  // RPC 는 service_role 전용(클라 직접 호출 차단). 신원은 검증된 JWT 에서 넘긴다.
  // fail-closed: RPC 실패면 발송하지 않는다.
  const { data, error } = await serviceClient().rpc('request_phone_otp', {
    p_user_id: auth.user.id,
    p_phone_hash: phoneHash,
    p_code_hash: codeHash,
    p_ttl_seconds: TTL_SECONDS,
    p_cooldown_seconds: COOLDOWN_SECONDS,
    p_hourly_cap: HOURLY_CAP,
    p_daily_global_cap: DAILY_GLOBAL_CAP,
    p_user_daily_cap: USER_DAILY_CAP,
  });
  if (error) {
    console.error('[send-otp] request_phone_otp failed:', error.message);
    return errorResponse('Verification temporarily unavailable', 503);
  }

  // RPC 결과를 단언하지 않고 검증한다. 형태가 다르면 발송하지 않는다(fail-closed).
  const result = data as Record<string, unknown> | null;
  if (!result || result.allowed !== true) {
    const reason = typeof result?.reason === 'string' ? result.reason : 'DENIED';
    const retryAfter = typeof result?.retry_after === 'number' ? result.retry_after : null;
    const res = errorResponse('요청이 제한되었습니다. 잠시 후 다시 시도하세요.', 429, { reason });
    if (retryAfter) res.headers.set('Retry-After', String(retryAfter));
    return res;
  }

  try {
    await sendSms(
      sensConfigFromEnv(),
      toDomesticKr(e164),
      `[올라운드] 인증번호 ${code} 를 입력해 주세요.`,
    );
  } catch (e) {
    console.error('[send-otp] SMS send failed:', (e as Error).message);
    return errorResponse('인증번호 발송에 실패했습니다. 잠시 후 다시 시도하세요.', 502);
  }

  return jsonResponse({ ok: true });
});
