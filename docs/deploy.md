# Match-up 배포 가이드

## 1. 사전 요구사항

- [Supabase CLI](https://supabase.com/docs/guides/cli) v2.100+
- Flutter 3.x / Dart 3.x
- Xcode (iOS), Android Studio (Android)
- Google Cloud Console 프로젝트 (OAuth + Gemini API)

## 2. Supabase 프로젝트

### 2.1 프로젝트 생성

```bash
# supabase.com에서 프로젝트 생성 (Region: Northeast Asia / ap-northeast-1)
supabase login
supabase link --project-ref <PROJECT_REF>
```

### 2.2 마이그레이션 적용

```bash
supabase db push
```

현재 51개 마이그레이션 파일이 순서대로 적용됩니다.

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
