# 크롤러 시스템

## 아키텍처

```
pg_cron → invoke_edge_function('crawl-dispatch') → INTERNAL_CRON_JWT 인증
                    ↓
          crawl-dispatch Edge Function
                    ↓
          crawl_sources 테이블에서 enabled + schedule 매칭 소스 조회
                    ↓
          parser_module별 파서 호출 → 게시판 파싱 → upsertTournament
```

## crawl-dispatch
- 단일 진입점: 모든 크롤러를 하나의 Edge Function으로 통합
- `POST { slug?, force? }` — slug 지정 시 해당 소스만, 미지정 시 전체 스케줄 실행
- `force=true` — schedule_cron 무시, 즉시 실행 (어드민 수동 트리거)
- `running_started_at` 잠금으로 중복 실행 방지

## crawl_sources 테이블
DB-driven 크롤러 소스 관리. 어드민 UI에서 CRUD 가능.

주요 필드:
- `slug` — 고유 식별자 (예: tennis-gwangju-board)
- `url` — listing 페이지 URL
- `parser_module` — 파서 모듈명 (코드에서 매칭)
- `schedule_cron` — 실행 주기 (예: "0 21 * * *")
- `enabled` — 활성화 여부
- `last_status` — ok / no_change / error

## 파서 모듈 (`_shared/crawler/parsers/`)
- `gnuboard_sub5_5_contest.ts` — 그누보드 게시판 파서 (광주/전남 테니스 사용)
- 파서별 `fetchListing()` + `fetchDetail()` 구현
- `fetchDetail()`에서 `extractSidoStdDivisions()` 호출하여 부서코드 추출

## 부서코드 추출 흐름
1. 상세 페이지 텍스트에서 `extractSidoStdDivisions(text, org)` 호출
2. `GJ_KEYWORD_TO_SUFFIX` 매핑으로 키워드 → 코드 변환
3. 결과: `eligible_grades` (코드 배열) + `division_label_local` (원본 텍스트)

## upsertTournament
- content-hash 기반 중복 방지 (force=true 시 우회)
- 기존 description이 있으면 보존 (크롤러 덮어쓰기 방지)
- `embedding = null` 설정하여 embed-pending 워커가 재임베딩

## 인증
- pg_cron 호출: `INTERNAL_CRON_JWT` (service_role JWT)
- 어드민 수동 실행: 사용자 JWT → requireServiceRoleOrAdmin 체크
- `SUPABASE_SERVICE_ROLE_KEY`는 reserved secret이라 삭제 불가 → INTERNAL_CRON_JWT 별도 운용

## 어드민 UI
- admin_screen.dart "크롤 소스" 탭: CRUD + 수동 실행 + 실행 결과 표시
- admin_screen.dart "크롤 현황" 탭: crawl_audit 로그 자동 갱신 (30초)
