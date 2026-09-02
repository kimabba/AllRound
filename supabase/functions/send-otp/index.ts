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
import { sendSms, solapiConfigFromEnv } from '../_shared/solapi.ts';
import { serviceClient } from '../_shared/supabase.ts';

const TTL_SECONDS = 180; // OTP 유효 3분
const COOLDOWN_SECONDS = 60; // 재발송 쿨다운
const HOURLY_CAP = 5; // 번호당 시간당 발송
const PHONE_DAILY_CAP = 10; // 번호당 일일 발송(계정 교체 우회 차단)
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
  let consent = false;
  try {
    const body: unknown = await req.json();
    raw = stringFieldOf(body, 'phone');
    consent = (body as Record<string, unknown> | null)?.consent === true;
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  // 동의는 화면 체크박스가 아니라 여기서 막는다. 클라이언트만 검사하면 JWT 로
  // 이 엔드포인트를 직접 호출해 우회할 수 있고, 그러면 동의 없이 번호를 받아
  // 수탁자에게 넘기는 셈이 된다(개인정보보호법 §15·§22).
  if (!consent) {
    return errorResponse('개인정보 수집·이용 및 위탁에 대한 동의가 필요합니다.', 400);
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

  // 동의를 받았다는 사실을 남긴다. 입증 책임은 우리에게 있고 화면 체크박스는 흔적이
  // 없다. 최초 시점을 보존하려고 이미 값이 있으면 덮어쓰지 않는다.
  // rate limit RPC **앞**에 둔다 — RPC 는 발송 카운터를 먼저 올리므로, 뒤에 두면
  // 기록 실패 시 문자는 안 나갔는데 시간당·일일 한도만 깎인다.
  const { error: consentError } = await serviceClient()
    .from('users')
    .update({ phone_consent_at: new Date().toISOString() })
    .eq('id', auth.user.id)
    .is('phone_consent_at', null);
  if (consentError) {
    console.error('[send-otp] consent record failed:', consentError.message);
    return errorResponse('Verification temporarily unavailable', 503);
  }

  // RPC 는 service_role 전용(클라 직접 호출 차단). 신원은 검증된 JWT 에서 넘긴다.
  // fail-closed: RPC 실패면 발송하지 않는다.
  const { data, error } = await serviceClient().rpc('request_phone_otp', {
    p_user_id: auth.user.id,
    p_phone_hash: phoneHash,
    p_code_hash: codeHash,
    p_ttl_seconds: TTL_SECONDS,
    p_cooldown_seconds: COOLDOWN_SECONDS,
    p_hourly_cap: HOURLY_CAP,
    p_phone_daily_cap: PHONE_DAILY_CAP,
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
      solapiConfigFromEnv(),
      toDomesticKr(e164),
      `[올라운드] 인증번호 ${code} 를 입력해 주세요.`,
    );
  } catch (e) {
    console.error('[send-otp] SMS send failed:', (e as Error).message);
    return errorResponse('인증번호 발송에 실패했습니다. 잠시 후 다시 시도하세요.', 502);
  }

  return jsonResponse({ ok: true });
});
