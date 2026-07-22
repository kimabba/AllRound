# Match-up 배포 가이드

## 1. 사전 요구사항

- [Supabase CLI](https://supabase.com/docs/guides/cli) v2.100+
- Flutter 3.x / Dart 3.x
- Xcode (iOS), Android Studio (Android)
- Google Cloud Console 프로젝트 (OAuth + Gemini API)

## 1.1 운영 배포/태그 관리 원칙

GitHub 태그는 버전 표시용이며, 태그 생성만으로 운영 배포가 실행되어서는 안 된다.
운영 배포는 별도 수동 실행과 승인 절차를 거친 뒤 진행한다.

- `main` 브랜치는 직접 push하지 않고 PR 기반으로 반영한다.
- 릴리즈 태그는 `v1.0.0` 같은 `v*` 형식만 사용한다.
- 릴리즈 태그 생성 권한은 지정된 담당자로 제한한다.
- 태그 삭제/재생성은 원칙적으로 금지한다.
- 운영 배포는 GitHub Environment `production` 승인 후 진행한다.
- 배포 실행자와 승인자는 분리한다. 실행자가 본인이면 백과장 승인, 백과장이 실행하면 본인 승인을 받는다.
- DB migration은 자동 배포하지 않는다. `supabase db push`는 변경 내용을 확인한 뒤 수동으로 적용한다.

권장 GitHub 설정:

- Ruleset: `main` 직접 push 제한, PR 필수, CI 통과 필수
- Ruleset: `v*` 태그 생성 권한 제한, 태그 삭제/수정 제한
- Environment: `production` required reviewers 설정, self-review 방지

## 2. Supabase 프로젝트

### 2.1 프로젝트 생성

```bash
# supabase.com에서 프로젝트 생성 (Region: Northeast Asia / ap-northeast-1)
supabase login
supabase link --project-ref <PROJECT_REF>
```

### 2.2 마이그레이션 적용

```bash
supabase db push --linked --dry-run   # 적용될 파일 먼저 확인
supabase db push --linked             # 실제 적용
```

`supabase/migrations/` 의 파일이 파일명 순서대로 적용됩니다. 적용 이력은
`supabase_migrations.schema_migrations` 에 **파일명 version 그대로** 기록됩니다.

**지켜야 할 것**

- **`apply_migration`(MCP)로 스키마를 적용하지 않는다.** 호출 시각으로 version 을 새로
  만들어 이력이 파일명과 어긋난다. 그렇게 83건이 어긋나 `db push` 가 막혔던 것이 JY-116 이고,
  2026-07-22 에 이력 127행을 정합화해 해소했다
  (경위·대응표: `docs/db/migration-history-repair-20260722.md`).
- **`046b_seed_futsal_venues.sql` 의 파일명을 고치지 않는다.** 규칙(`<version>_name.sql`)에
  안 맞아 CLI 가 항상 건너뛰는데, 내용은 이미 프로덕션에 적용돼 있다. 이름을 고치면
  `db push` 가 시드를 재실행한다.
- 이력이 다시 어긋나면 `supabase migration repair --linked --status applied|reverted <version>`
  으로 맞춘다. `reverted` 는 행을 **삭제**하므로 실행 전 `supabase migration fetch` 로
  원격 SQL 본문을 백업한다.

### 2.3 Secrets 설정

```bash
supabase secrets set \
  GEMINI_API_KEY=<your-gemini-api-key> \
  GEMINI_MODEL=gemini-2.0-flash \
  GEMINI_EMBEDDING_MODEL=gemini-embedding-001
```

운영 시 추가:
```bash
supabase secrets set CORS_ALLOW_ORIGIN=https://your-domain.com
supabase secrets set FCM_PROJECT_ID=<firebase-project-id>
supabase secrets set FCM_SERVICE_ACCOUNT='<service-account-json>'
```

### 2.4 Auth 설정

Supabase Dashboard > Authentication > Providers:
- **Google**: Client ID / Secret 등록
- **Email**: 가입 활성화, 이메일 인증 비활성화 (권장)

### 2.5 Cron 설정 (pg_cron)

Supabase Dashboard > SQL Editor에서 실행:
```sql
-- Edge Function 호출 URL/키 설정
ALTER DATABASE postgres SET app.cron_invoke_url = 'https://<ref>.supabase.co/functions/v1';

-- 매시간 알림 발송
SELECT cron.schedule('notify-hourly', '0 * * * *',
  $$SELECT net.http_post(
    url := current_setting('app.cron_invoke_url') || '/notify-cron',
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.cron_invoke_key'))
  )$$
);

-- 6시간마다 크롤링
SELECT cron.schedule('crawl-6h', '0 */6 * * *',
  $$SELECT net.http_post(
    url := current_setting('app.cron_invoke_url') || '/crawl-dispatch',
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.cron_invoke_key'))
  )$$
);

-- 5분마다 임베딩 생성
SELECT cron.schedule('embed-5m', '*/5 * * * *',
  $$SELECT net.http_post(
    url := current_setting('app.cron_invoke_url') || '/embed-pending',
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.cron_invoke_key'))
  )$$
);
```

## 3. Edge Functions 배포

```bash
PROJECT_REF=<your-project-ref>

# 일반 함수 (JWT 검증 필요)
for fn in chat chat-history \
  clubs-approve clubs-create clubs-join clubs-review-join clubs-search \
  semantic-search tournaments-approve tournaments-search tournaments-submit \
  health; do
  supabase functions deploy $fn --project-ref $PROJECT_REF \
    --import-map=supabase/functions/deno.json
done

# Cron 함수 (JWT 검증 불필요)
for fn in embed-pending notify-cron crawl-dispatch; do
  supabase functions deploy $fn --project-ref $PROJECT_REF \
    --import-map=supabase/functions/deno.json --no-verify-jwt
done
```

## 4. Flutter 앱 빌드

### 4.1 환경변수

`app/.env.local` 생성 (`.env.local.example` 참고):
```json
{
  "SUPABASE_URL": "https://<ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<publishable-anon-key>",
  "API_BASE_URL": ""
}
```

### 4.2 빌드

```bash
cd app

# iOS
flutter build ipa --dart-define-from-file=.env.local

# Android
flutter build appbundle --dart-define-from-file=.env.local
```

### 4.3 주의사항

- macOS 개발: `make app` 사용 (자동으로 `--dart-define-from-file` 적용)
- 웹 빌드: 어드민 전용 (`make admin`)
- `dev-auth` 함수는 프로덕션에 배포하지 말 것

## 5. 스토어 제출

### App Store (iOS)
- Bundle ID: `io.matchup.app`
- 카테고리: 스포츠
- 등급: 4+
- 개인정보처리방침 URL 필수

### Google Play (Android)
- Application ID: `io.matchup.app`
- 카테고리: 스포츠
- 콘텐츠 등급: 전체이용가
- 개인정보처리방침 URL 필수

## 6. 로컬 개발

```bash
make setup    # 최초 1회: Docker + Supabase 로컬 시작
make backend  # Edge Functions 핫리로드 (원격 DB 사용)
make app      # Flutter macOS 앱 실행
make admin    # 웹 어드민 대시보드
make check    # 정적 검증 (flutter analyze + deno lint)
make reset    # 앱 캐시 초기화
```

## 7. 모니터링

- **Supabase Dashboard**: Functions Logs, Database Queries
- **Edge Function 헬스체크**: `GET /health` 엔드포인트
- **크롤링 감사**: `crawl_audit` 테이블 조회
- **알림 이력**: `notifications_log` 테이블 조회
