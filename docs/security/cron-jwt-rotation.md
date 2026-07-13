# INTERNAL_CRON_JWT 로테이션 런북

## 배경

`invoke_edge_function`(pg_cron → Edge Function 호출)이 사용하는 `INTERNAL_CRON_JWT`
(service_role 권한 JWT)가 migration `030`에 **평문으로 하드코딩**되어 공개 레포에
노출되었다. service_role JWT 는 RLS 를 우회하므로 노출 시 DB 전체가 위험하다.

이 문서는 노출된 키를 **무효화**하고, 코드를 Vault 기반으로 전환하는 절차다.

> 노출된 키는 이미 유출된 것으로 간주한다. 코드에서 지워도 git 히스토리·CI 로그에
> 남아 있으므로 **키 무효화(로테이션)** 가 반드시 필요하다.

## 코드 변경 (이 PR 에서 완료)

- `030_...sql`: 평문 JWT 제거 → `vault.decrypted_secrets` 에서 `internal_cron_jwt` 조회
- `034_invoke_edge_function_use_vault.sql`: 운영 DB 함수를 Vault 버전으로 교체

코드만으로는 노출된 키가 무효화되지 않는다. 아래 운영 절차를 반드시 수행한다.

## 운영 절차 (대시보드 + SQL)

### 1. 키 로테이션 — 노출된 JWT 무효화

Supabase 대시보드 → **Project Settings → JWT Keys** → **JWT Signing Keys** 탭

1. **Rotate Keys** 클릭 (현재 키가 "Previously used keys" 로 이동)
2. 이전 키의 ⋯(액션) → **Revoke** — Revoke 하지 않으면 옛 키가 계속 유효하다
3. (아직 asymmetric signing key 로 마이그레이션 전이면 먼저 마이그레이션 필요:
   https://supabase.com/docs/guides/auth/signing-keys#getting-started )

> ⚠️ 로테이션하면 anon/service_role 등 모든 키가 함께 바뀐다. 아래 4·5단계에서
> 앱·CI·Edge Function 환경변수를 새 값으로 교체해야 하며, 그 사이 잠깐 인증이
> 끊길 수 있다. 사용량이 적은 시간대에 수행한다.

참고: 유출 대응 공식 가이드 —
https://supabase.com/docs/guides/getting-started/api-keys#what-to-do-if-a-secret-key-or-servicerole-has-been-leaked-or-compromised

### 2. 새 INTERNAL_CRON_JWT 발급

cron 전용 랜덤 secret 을 발급한다. 이 값은 Supabase JWT가 아니며, pg_cron 호출과
Edge Function `INTERNAL_CRON_JWT` env var 비교에만 사용한다.

### 3. Vault 에 저장

```sql
select vault.create_secret('<새_INTERNAL_CRON_JWT>', 'internal_cron_jwt');
-- 이미 존재하면:
-- select vault.update_secret(
--   (select id from vault.secrets where name = 'internal_cron_jwt'),
--   '<새_INTERNAL_CRON_JWT>'
-- );
```

### 4. 034 마이그레이션 적용

Vault 에 secret 을 저장한 **다음** 함수를 교체한다 (secret 이 없으면 cron 이 실패).

```
supabase db push   # 또는 034 SQL 을 대시보드 SQL Editor 에서 실행
```

### 5. 환경변수 교체

- Edge Function: `INTERNAL_CRON_JWT` = 2단계의 새 랜덤 secret
- (로테이션으로 바뀐 경우) 앱·CI 의 anon/service_role 키도 새 값으로 교체

### 6. 검증

```sql
-- Vault 조회 확인
select name from vault.decrypted_secrets where name = 'internal_cron_jwt';

-- 함수 동작 확인 (request_id 가 반환되면 정상)
select public.invoke_edge_function('embed-pending', '{}'::jsonb);
```

- cron job 로그(`net._http_response`)에서 401/403 이 사라졌는지 확인
- 옛 키로 호출 시 거부되는지 확인 (Revoke 반영)

## 진행 상태 (2026-05-29 업데이트)

- ✅ cron 비밀번호를 service_role JWT → 랜덤값으로 분리 (Vault `internal_cron_jwt`, 96자)
- ✅ 034 마이그레이션 원격 적용, `invoke_edge_function` 이 Vault 사용 (200 검증 완료)
- ✅ Edge Function `INTERNAL_CRON_JWT` env 교체
- ✅ 레포 PRIVATE 전환 (추가 노출 차단)
- ✅ `notify-cron` 인증 가드 수정: `requireServiceRole` → `requireServiceRoleOrAdmin`
  - pg_cron이 INTERNAL_CRON_JWT(랜덤값)로 호출 시 `requireServiceRole`은 SERVICE_ROLE_KEY와
    비교하므로 403 거부되는 버그. `requireServiceRoleOrAdmin`은 cron secret을 우선 체크하여 정상 통과.
- ✅ `crawl-dispatch` config.toml 에 `verify_jwt = false` 추가
  - INTERNAL_CRON_JWT가 랜덤값이므로 Supabase 의 JWT 검증(`verify_jwt = true` 기본값)이
    핸들러 도달 전 401 반환. `net._http_response` 에서 간헐 401 확인됨.
- ✅ 앱을 publishable key(`sb_publishable_...`)로 전환 (2026-05-31)
- ✅ Legacy `anon`/`service_role` JWT-based API keys **Disabled** (2026-05-31)
- ✅ Legacy HS256 Shared Secret **Revoked** (2026-05-31)
- ✅ Revoke 후 cron 전부 200 정상 동작 확인
- ✅ 노출 JWT REST 호출 401 확인 (2026-07-10)
- ✅ Edge Function service-level 호출에서 legacy JWT 형태 거부 (2026-07-10)
  - `seed-intent-examples`가 `verify_jwt=true` 기본값 + `SUPABASE_SERVICE_ROLE_KEY`
    Bearer 비교로 노출 JWT를 받아들이는 회귀를 발견.
  - `requireServiceRole`은 이제 `sb_secret_...` secret API key만 허용하고,
    `seed-intent-examples`도 `verify_jwt=false` + 함수 내부 인증으로 통일.

## 노출 키 완전 차단 — legacy → 새 API 키 마이그레이션 (별도 세션)

노출된 service_role JWT 는 legacy HS256 JWT secret 으로 서명되어 있다. 이를 revoke
하려면 먼저 legacy JWT-based API keys(`anon`/`service_role`)를 비활성화해야 한다
(같은 secret 을 공유하므로, revoke 시 정상 anon 키까지 함께 무효화되기 때문).
→ 새 publishable/secret API key 체계로 전환이 선행되어야 한다.

**영향 범위**
- 앱: `--dart-define=SUPABASE_ANON_KEY` 를 `sb_publishable_...` 로 교체 후 재빌드 (코드 변경 없음)
- service_role 사용 Edge Function 5곳: `embed-pending`, `notify-cron`, `crawl-dispatch`,
  `seed-intent-examples`, `_shared/supabase.ts`(serviceClient) — 새 secret key 동작 검증 필요
- `notify-cron` 은 cron secret 인증 누락 버그가 있었으며 `requireServiceRoleOrAdmin` 으로 수정 완료
- `seed-intent-examples` 도 새 secret API key를 함수 내부에서 검증하도록 `verify_jwt=false` 필요

**절차**
1. Settings → API Keys 에서 publishable/secret key 발급·확인
2. (전환기) legacy 와 새 키가 병행 동작하므로, 새 키로 앱·Edge 동작 먼저 검증
3. 앱 재빌드: `SUPABASE_ANON_KEY = sb_publishable_...`
4. Edge Function 의 service client가 `SUPABASE_SECRET_KEYS.default = sb_secret_...` 로 정상 동작하는지 확인
5. API Keys → `anon`/`service_role` legacy 키 **Disable**
6. JWT Keys → Legacy HS256 (Shared Secret) → **Revoke**
7. 검증: 노출 JWT 로 REST 호출 시 **401**, service-level Edge Function 호출 시 **403/401** 확인
   ```
   curl -s -o /dev/null -w "%{http_code}" \
     -H "apikey: <노출JWT>" -H "Authorization: Bearer <노출JWT>" \
     "https://bsjdgwmveokanclqwtvx.supabase.co/rest/v1/users?select=id&limit=1"
   ```

**참고**
- 새 API keys: https://supabase.com/docs/guides/api/api-keys
- JWT Signing Keys: https://supabase.com/docs/guides/auth/signing-keys

## 재발 방지

- 시크릿은 SQL/코드에 하드코딩하지 않고 Vault 또는 환경변수에서 읽는다
- `scripts/harness/check_secrets.sh` 가 PR 에서 평문 시크릿을 차단한다
