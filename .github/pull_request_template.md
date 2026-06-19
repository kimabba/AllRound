## 요약

-

## 작업 영역

해당되는 항목을 체크하고, 필요한 규칙 문서를 읽어주세요.

- [ ] Flutter/UI — `docs/rules/FRONTEND_RULES.md`
- [ ] Edge Functions/API — `docs/rules/BACKEND_RULES.md`
- [ ] DB/RLS/RPC/Migration — `docs/rules/DATABASE_RULES.md`
- [ ] Tournament/grade/domain — `docs/rules/DOMAIN_RULES.md`
- [ ] Auth/security/AI/RAG/cron — `docs/rules/SECURITY_RULES.md`
- [ ] Speed Gun/video — `docs/rules/SPEED_GUN_RULES.md`
- [ ] CI/harness/rules — `docs/rules/HARNESS.md`

## 마이그레이션 배포 (DB 변경 시 필수)

> ⚠️ **머지 ≠ 프로덕션 적용.** 마이그레이션은 머지 후 자동 적용되지 않으므로, 누군가 수동으로 적용해야 한다. 절차: `docs/rules/DATABASE_RULES.md` → "마이그레이션 배포".

- [ ] 이 PR은 마이그레이션/데이터 변경을 **포함하지 않음** (포함하면 아래 작성)
- [ ] 포함하는 마이그레이션 파일: `supabase/migrations/___`
- [ ] 프로덕션 적용 담당: @___
- [ ] 적용 시점: 머지 직후 즉시 (지연 시 사유: ___)
- [ ] 데이터 시드는 `published` 직접 INSERT가 아닌 **어드민 검수 화면** 경유 (검수 큐 우회 금지)
- [ ] PR 본문의 "변경 범위" 설명이 실제 변경과 일치함 (예: "DB 변경 없음"인데 마이그레이션 포함 ❌)

## 하네스 체크

- [ ] `scripts/harness/run_all.sh` 통과
- [ ] 또는 아래 개별 체크 통과:
  - [ ] `python3 scripts/harness/check_enums.py`
  - [ ] `python3 scripts/harness/check_static_rules.py`
  - [ ] `bash scripts/harness/check_secrets.sh`
  - [ ] `cd app && flutter analyze && flutter test`
  - [ ] `cd supabase/functions && deno fmt --check */index.ts _shared/*.ts tests/*.ts && deno lint --config deno.json */index.ts _shared/*.ts tests/*.ts && deno check --config deno.json */index.ts _shared/*.ts tests/*.ts && deno test --config deno.json --allow-env --allow-read tests`

## 팀 리뷰 포인트

- [ ] 서버/DB가 최종 판정자인가? 클라이언트만 믿고 있지 않은가?
- [ ] 새 입력값에 validation과 길이 제한이 있는가?
- [ ] 새 테이블은 RLS + 정책이 있는가?
- [ ] enum/label 값이 Dart/TS/SQL 사이에서 동기화되어 있는가?
- [ ] AI/RAG/외부 크롤링 데이터는 untrusted data로 취급되는가?
- [ ] 스피드건 결과는 낮은 품질 입력에 대해 경고/차단/낮은 신뢰도를 표시하는가?

## 스크린샷 / 로그

필요 시 첨부.
