import { createClient, SupabaseClient } from '@supabase/supabase-js';

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

function getNamedKey(envName: string, fallbackName: string): string {
  const encoded = Deno.env.get(envName);
  if (encoded) {
    try {
      const parsed = JSON.parse(encoded) as unknown;
      if (parsed && typeof parsed === 'object') {
        const keys = parsed as Record<string, unknown>;
        const defaultKey = keys.default;
        if (typeof defaultKey === 'string' && defaultKey) return defaultKey;
      }
    } catch {
      // Fall through to compatibility fallback.
    }
  }
  return requireEnv(fallbackName);
}

/**
 * 사용자 JWT 권한으로 Supabase에 접근하는 클라이언트.
 * RLS가 적용되므로 일반 사용자 요청에 사용한다.
 */
export function userClient(authHeader: string | null): SupabaseClient {
  const url = requireEnv('SUPABASE_URL');
  const anon = getNamedKey('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
  return createClient(url, anon, {
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
    auth: { persistSession: false },
  });
}

/**
 * service_role 권한 클라이언트. RLS 우회. 크롤러·cron·관리자 작업 전용.
 */
export function serviceClient(): SupabaseClient {
  const url = requireEnv('SUPABASE_URL');
  const key = getNamedKey('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
