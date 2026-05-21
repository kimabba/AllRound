# 크롤링 sources 어드민 관리 v1

## 목표
- 크롤링 대상 사이트를 어드민이 UI 에서 등록/수정/삭제 + 활성화 토글
- 검수 워크플로우 강화 (draft → admin approve → published)
- 변경 감지 (ETag / Last-Modified) 로 무의미한 fetch 회피

## 영향 받는 파일 (Phase 단위)

### Phase 1 (완료)
- `supabase/migrations/019_crawl_sources.sql` (신규)
- `app/lib/models/crawl_source.dart` (신규)
- `app/lib/services/api.dart` (CrawlSource CRUD 메서드)
- `app/lib/screens/admin/admin_screen.dart` (Tab 2 DB-driven)

### Phase 2 (대기)
- `supabase/functions/crawl-dispatch/index.ts` (신규) — `crawl_sources` 순회 + `parser_module` 매핑 호출
- `supabase/functions/_shared/crawler.ts` (확장) — parser 모듈 등록 / dispatch
- `supabase/functions/crawl-tennis-{gwangju,jeonnam,korea}/index.ts` → 파서 모듈로 리팩토 (단일 호출 진입점)
- `supabase/migrations/{NNN}_cron_dispatcher.sql` (신규) — pg_cron 일원화

### Phase 3 (대기)
- 어드민 Tab 1 (드래프트 검수) 강화 — 일괄 승인/거부 + 필터
- `supabase/functions/tournaments-approve/index.ts` (확장) — bulk approve

### Phase 4 (대기)
- `crawl_sources.last_etag / last_modified` 활용 — conditional GET
- 새 사이트 추가 + 사용자 제보 시스템 활성화 (이미 `tournaments_user_submit` 정책 있음)

## Phase 별 작업

### Phase 1 — 인프라 (완료)
- [x] `crawl_sources` 테이블 + `crawl_source_type` enum + RLS (admin / service_role)
- [x] 시드 3개 (광주테니스/전남/한국, 실제 LIST_URL)
- [x] Flutter `CrawlSource` 모델 + REST CRUD
- [x] AdminScreen Tab 2 DB-driven + CRUD 다이얼로그
- [x] "수동 실행" 버튼 disabled (Phase 2 까지)

### Phase 2 — Dispatcher (대기)
- [ ] `crawl-dispatch` Edge Function — `crawl_sources` 순회, `parser_module` 매핑 호출, `crawl_audit.source = crawl_sources.slug` 일관
- [ ] 기존 크롤러 → parser 모듈로 리팩토 (`_shared/crawler/parsers/{tennis-gwangju-board,...}.ts`)
- [ ] **⚠️ pg_cron 전환 (중복 실행 회피)**:
  1. 새 cron job 추가: `*/15 * * * *` → `crawl-dispatch` (매 15분 호출, dispatcher 내부에서 source 별 `schedule_cron` 비교해 실행 대상 판정)
  2. 기존 3개 cron job (`crawl-tennis-gwangju`, `crawl-tennis-jeonnam`, `crawl-tennis-korea`) **DROP**
  3. 마이그레이션에 `select cron.unschedule('crawl-tennis-gwangju'); ...` 포함
  - 시드 데이터의 `schedule_cron` (`0/15/30 21 * * *`) 이 기존 cron 과 동일 → 전환 시 dispatcher 가 자체 실행 → 중복 없음
- [ ] AdminScreen "수동 실행" 버튼 활성화 → `crawl-dispatch?slug=xxx&force=true`

### Phase 3 — 검수 워크플로우 강화 (대기)
- [ ] 크롤러가 INSERT 시 `status='draft'` 강제 (기존 동작 확인)
- [ ] 어드민 Tab 1 일괄 승인/거부 + 사유 입력
- [ ] 거부된 항목은 `status='rejected'` 로 마킹 → 재크롤 시 중복 회피
- [ ] 사용자 제보 (`tournaments_user_submit`) 도 같은 큐에서 검수

### Phase 4 — 변경 감지 + 새 사이트 (대기)
- [ ] dispatcher 가 fetch 시 conditional GET 헤더 (`If-None-Match`, `If-Modified-Since`) 전송
- [ ] 304 응답 시 `last_status='no_change'` 기록, 본문 처리 skip
- [ ] 새 사이트 추가 (KTA 외 지역 협회들) — 어드민 UI 에서 직접

## 피해야 할 함정
- **pg_cron 중복 실행** — Phase 2 전환 시 기존 cron job 반드시 DROP
- **slug 변경** — unique 키이므로 수정 다이얼로그에서 disabled (이미 적용됨)
- **service_role key 클라이언트 노출 금지** — RLS 정책으로 admin 격리 확인
- **robots.txt 무시** — Phase 2 dispatcher 가 사이트별 robots.txt 체크 후 fetch
- **악의적 URL 등록** — 어드민 UI 에 URL allowlist 추가 검토 (Phase 4)

## 측정 기준
- 어드민이 UI 에서 신규 source 추가 → Phase 2 dispatcher 가 자동 인식
- `crawl_audit` 의 `source` 컬럼이 `crawl_sources.slug` 와 일치
- 변경 없는 fetch 비율 = `last_status='no_change'` / total (Phase 4 효과 지표)

## Dependencies
- **DB**: PostgreSQL 17 + pgvector + pg_cron + pg_net + uuid_generate_v7() (015 + 017)
- **Edge Functions**: Deno + Supabase Functions
- **Flutter**: 기존 Riverpod + Supabase Flutter SDK

## Limitations
- Phase 1 만으로는 어드민 추가/수정이 실제 크롤링에 영향 없음 (Phase 2 dispatcher 도입 전까지 기존 cron 으로만 동작)
- 시드 3개 외 신규 source 는 Phase 2 도입 후에만 자동 실행

## Future Work
- 사용자 제보 시스템 활성화 (Phase 3 검수와 통합)
- 공식 API/RSS 파트너십 협회별 협의 (협회 데이터 직접 받기)
- Slack/email 실패 알림 (dispatcher 가 error 시 발송)
- 모니터링 대시보드 (success rate / 최근 N 일 fetched 합계)

## 관련 문서
- 백엔드 룰: [`../rules/BACKEND_RULES.md`](../rules/BACKEND_RULES.md)
- 보안 룰: [`../rules/SECURITY_RULES.md`](../rules/SECURITY_RULES.md)
- 도메인 룰: [`../rules/DOMAIN_RULES.md`](../rules/DOMAIN_RULES.md)
