import { SupabaseClient } from '@supabase/supabase-js';
import { userClient } from './supabase.ts';
import { errorResponse } from './cors.ts';

export interface AuthedUser {
  id: string;
  email: string | null;
  isAdmin: boolean;
}

/**
 * Authorization 헤더의 JWT 를 검증하고 public.users 의 role 을 합쳐 반환.
 * 인증 실패 시 Response 를 반환하므로 호출 측에서 분기한다.
 */
export async function requireUser(
  req: Request,
): Promise<{ user: AuthedUser; supabase: SupabaseClient } | { error: Response }> {
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
