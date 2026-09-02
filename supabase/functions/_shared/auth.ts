import { SupabaseClient } from '@supabase/supabase-js';
import { userClient } from './supabase.ts';
import { errorResponse } from './cors.ts';

export interface AuthedUser {
  id: string;
  email: string | null;
  isAdmin: boolean;
}

type UserAuthResult =
  | { user: AuthedUser; supabase: SupabaseClient }
  | { error: Response };

/**
 * Authorization 헤더의 JWT 를 검증하고 public.users 의 role 을 합쳐 반환.
 * 인증 실패 시 Response 를 반환하므로 호출 측에서 분기한다.
 */
export async function requireUser(
  req: Request,
): Promise<UserAuthResult> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return { error: errorResponse('Missing Authorization header', 401) };
  }

  const supabase = userClient(authHeader);
  const { data: userData, error } = await supabase.auth.getUser();
  if (error || !userData.user) {
    return { error: errorResponse('Invalid or expired token', 401) };
  }

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', userData.user.id)
    .maybeSingle();

  return {
    supabase,
    user: {
      id: userData.user.id,
      email: userData.user.email ?? null,
      isAdmin: profile?.role === 'admin',
    },
  };
}

/**
 * 현재 JWT 사용자의 만 14세 이상 생년월일 저장 여부를 DB 기준으로 확인한다.
 * 사용자 클라이언트를 받아 RLS와 같은 auth.uid() 경계에서 판정한다.
 */
export async function requireVerifiedAge(
  supabase: SupabaseClient,
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('has_verified_signup_age');
  if (error) {
    return errorResponse('Age verification unavailable', 500);
  }

  const verified: unknown = data;
  if (verified !== true) {
    return errorResponse(
      'AGE_VERIFICATION_REQUIRED: 만 14세 이상 생년월일 등록이 필요합니다.',
      403,
    );
  }
  return null;
}

/**
 * 인증과 서버 연령 검증을 함께 요구하는 guard.
 *
 * 주의: 전화번호 인증은 여기 넣지 않는다. send-otp 가 이 guard 를 쓰므로
 * 자격에 전화인증을 포함시키면 "인증하려면 인증돼 있어야 하는" 순환이 된다.
 * 참여(사회적 쓰기) endpoint 는 아래 requireEligibleMember 를 쓴다.
 */
export async function requireVerifiedUser(req: Request): Promise<UserAuthResult> {
  const result = await requireUser(req);
  if ('error' in result) return result;

  const ageError = await requireVerifiedAge(result.supabase);
  if (ageError) return { error: ageError };
  return result;
}

/**
 * 계정 자격(연령 + 전화번호 인증)을 DB 술어로 확인한다.
 * 판정 정본은 public.is_eligible_member() 이며, 최종 강제는 RLS 가 한다.
 * 이 함수는 빠른 실패와 사용자에게 보여줄 에러 메시지를 위한 층이다.
 */
export async function requireEligibility(
  supabase: SupabaseClient,
): Promise<Response | null> {
  const { data, error } = await supabase.rpc('is_eligible_member');
  if (error) {
    return errorResponse('Eligibility check unavailable', 500);
  }
  if (data !== true) {
    return errorResponse(
      'PHONE_VERIFICATION_REQUIRED: 전화번호 인증이 필요합니다.',
      403,
    );
  }
  return null;
}

/** 인증 + 계정 자격을 함께 요구하는 참여·비용 발생 endpoint용 guard. */
export async function requireEligibleMember(req: Request): Promise<UserAuthResult> {
  const result = await requireUser(req);
  if ('error' in result) return result;

  const eligibilityError = await requireEligibility(result.supabase);
  if (eligibilityError) return { error: eligibilityError };
  return result;
}

export async function requireAdmin(req: Request) {
  const result = await requireUser(req);
  if ('error' in result) return result;
  if (!result.user.isAdmin) {
    return { error: errorResponse('Admin only', 403) };
  }
  return result;
}

export function requireServiceRole(
  req: Request,
): { error: Response } | Record<string, never> {
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.replace('Bearer ', '').trim();
  if (!token) {
    return { error: errorResponse('Missing token in Authorization header', 401) };
  }

  // Legacy service_role JWTs are permanently compromised for this project.
  // Only the new opaque Supabase secret API keys may be used for service-level invocation.
  if (!token.startsWith('sb_secret_')) {
    return { error: errorResponse('Forbidden: Legacy service JWTs are not accepted', 403) };
  }

  const serviceKeys = getSecretApiKeys();
  if (!serviceKeys.includes(token)) {
    return { error: errorResponse('Forbidden: Invalid Secret API Key', 403) };
  }
  return {};
}

function getSecretApiKeys(): string[] {
  const keys: string[] = [];
  const encoded = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (encoded) {
    try {
      const parsed = JSON.parse(encoded) as unknown;
      if (parsed && typeof parsed === 'object') {
        for (const value of Object.values(parsed as Record<string, unknown>)) {
          if (typeof value === 'string' && value.startsWith('sb_secret_')) {
            keys.push(value);
          }
        }
      }
    } catch {
      // Fall through to explicit env fallbacks.
    }
  }

  for (const name of ['SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
    const value = Deno.env.get(name);
    if (value?.startsWith('sb_secret_')) keys.push(value);
  }
  return keys;
}

// pg_cron / invoke_edge_function 에서 사용하는 내부 호출 인증.
// SUPABASE_SERVICE_ROLE_KEY 가 platform 버전에 따라 달라질 수 있어,
// INTERNAL_CRON_JWT env var 를 별도로 설정해 비교한다.
export function requireCronSecret(
  req: Request,
): { error: Response } | Record<string, never> {
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.replace('Bearer ', '').trim();
  const cronJwt = Deno.env.get('INTERNAL_CRON_JWT');
  if (cronJwt && token === cronJwt) return {};
  return { error: errorResponse('Forbidden: Invalid Internal Token', 403) };
}

export function requireServiceRoleOrAdmin(
  req: Request,
): Promise<{ error: Response } | Record<string, never>> {
  // 1) cron secret (pg_cron / invoke_edge_function 내부 호출)
  const cronResult = requireCronSecret(req);
  if (!('error' in cronResult)) return Promise.resolve({});
  // 2) Supabase secret API key (sb_secret_...), never legacy service_role JWT
  const srResult = requireServiceRole(req);
  if (!('error' in srResult)) return Promise.resolve({});
  // 3) admin 사용자 JWT
  return requireAdmin(req).then((r) => ('error' in r ? r : ({} as Record<string, never>)));
}
