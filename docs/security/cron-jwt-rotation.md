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

로테이션 후 새 키 기준으로 cron 전용 service_role JWT 를 발급한다.
(기존과 동일한 방식으로 재발급 — service_role 클레임 JWT)

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

- Edge Function: `INTERNAL_CRON_JWT` = 2단계의 새 JWT
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

## 재발 방지

- 시크릿은 SQL/코드에 하드코딩하지 않고 Vault 또는 환경변수에서 읽는다
- `scripts/harness/check_secrets.sh` 가 PR 에서 평문 시크릿을 차단한다
