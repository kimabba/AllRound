# 지식베이스 1단계 — 룰북·지식 문서 관리 설계

날짜: 2026-05-27
상태: 설계 확정 (grill-me 인터뷰 완료) → 구현 계획 대기

## Context

챗봇(RAG)과 대회 기능이 활용하는 정보를 관리자가 체계적으로 확인·검토·수정·활용할 **백오피스(지식베이스)**가 필요하다. 앱 사용자용이 아니라 운영자용 시스템이다.

현재 챗봇 RAG가 참조하는 `rule_articles`(룰북, 임베딩)와 `intent_examples`(의도 분류)는 **관리 UI가 전혀 없어** DB·스크립트로만 다룬다. 어드민 콘솔(`admin_screen.dart`)에는 크롤/검수 탭만 있다.

지식베이스는 세 영역으로 단계적으로 구축한다:
1. **(이 문서) 룰북·지식 문서 관리** — `rule_articles` CRUD + 임베딩 상태/재계산
2. 의도분류 예시 관리 — `intent_examples` (후속)
3. Q&A 캐시·챗봇 품질 모니터링 (후속)

어드민 콘솔 사이드바형 IA 재설계는 별도 후속. 이번 1단계는 기존 탭 구조에 "지식베이스" 탭을 추가하되, 모놀리식(1485줄) `admin_screen.dart`에서 **신규 탭만 별도 파일로 분리**해 점진적 리팩토링을 시작한다.

## 범위

### 포함 (1단계)
- `rule_articles` 목록 조회 (종목·카테고리 필터, published 무관 전체)
- 작성/수정/삭제 (sport·category·title·body 마크다운·order_idx·published)
- 게시(published) 토글
- 임베딩 상태 표시(대기/최신) + **즉시 재계산** 버튼
- 어드민 "지식베이스" 탭 신설 (신규 파일)

### 제외 (후속)
- 의도분류 예시 / Q&A 모니터링 (2·3단계)
- 어드민 사이드바 IA 전면 재설계
- 지식 검색 테스트(semantic-search 미리보기)
- `order_idx` 드래그 재정렬 (숫자 입력으로 대체)
- soft-delete (hard delete + 게시 취소로 대체)

## 데이터 모델

**신규 마이그레이션 없음.** 기존 `rule_articles`(005_chat_rules.sql) 사용:
```
id, sport(enum), category(text 자유), title, body(markdown),
order_idx(int), published(bool),
embedding vector(768), embedding_updated_at, created_at, updated_at
```
- RLS: `rule_articles_admin_all`(admin 전체 CRUD) + `rule_articles_authenticated_read`(published read) — **이미 존재**
- 트리거 `invalidate_rule_embedding()`: title/body 변경 시 `embedding` **및** `embedding_updated_at`을 둘 다 null로 — **이미 존재**

### 임베딩 상태 판정 (2가지)
트리거가 변경 즉시 둘 다 null로 만들므로 "stale" 중간 상태는 존재하지 않는다:
- `embedding_updated_at IS NULL` → **임베딩 대기**
- `embedding_updated_at IS NOT NULL` → **최신**

→ `embedding` vector 컬럼은 **select하지 않는다** (무겁고 불필요). `embedding_updated_at`만으로 판정.

## 백엔드

**신규 Edge Function 없음. 기존 1개 함수만 1줄 수정:**
- `embed-pending/index.ts`: 인증을 `requireServiceRole` → `requireServiceRoleOrAdmin`으로 교체 (cron secret/service_role에 더해 admin JWT 허용). `_shared/auth.ts`에 헬퍼가 이미 존재. config.toml `verify_jwt=false`는 유지(함수 내부에서 검증). → admin이 즉시 재계산 호출 가능. 재배포 필요.

룰 CRUD는 Flutter가 admin RLS로 `rule_articles`를 직접 처리(별도 Edge 불필요).

## Flutter

### API (`app/lib/services/api.dart`)
- `adminListRules({String? sport})` — `rule_articles` 전체(published 무관). select 컬럼에서 `embedding` 제외, `embedding_updated_at`·`updated_at`·`order_idx`·`published` 포함. 정렬 `sport, category, order_idx`
- `createRule(Map)` / `updateRule(id, Map)` / `deleteRule(id)` — 직접 supabase (admin RLS)
- `recomputeRuleEmbedding(id)` — ① 해당 행 `embedding=null, embedding_updated_at=null` update ② `embed-pending` POST 호출(admin JWT, 기존 `_uri`/`_authHeaders` 패턴) → 즉시 재임베딩
- 신규 작성 order_idx 기본값: 해당 (sport, category)의 `max(order_idx)+1` 조회 헬퍼

### Model (`app/lib/models/tournament.dart` 의 `RuleArticle`)
현재 필드 `id, sport, category, title, body`만 존재 → 다음 추가:
`orderIdx(int)`, `published(bool)`, `embeddingUpdatedAt(DateTime?)`, `updatedAt(DateTime?)`.
`embedding` vector는 모델에 두지 않음. 임베딩 상태는 `embeddingUpdatedAt == null` 여부로 getter 제공.
(주의: 기존 `listRules`/`rules_screen`이 `RuleArticle.fromJson`을 쓰므로, 추가 필드는 모두 nullable 또는 기본값으로 두어 기존 호출 깨지지 않게 한다.)

### Providers (`app/lib/state/providers.dart`)
- `adminRulesProvider` (FutureProvider.autoDispose) — admin 전체 룰 목록. 작업 후 invalidate로 새로고침.

### 화면
- `app/lib/screens/admin/knowledge_base_tab.dart` (신규): 목록 위젯
  - 상단: 종목/카테고리 필터
  - 목록: 제목·카테고리·게시여부·**임베딩 상태 뱃지(대기/최신)**. 탭 시 편집 화면 push
  - 신규 작성 FAB
- `app/lib/screens/admin/rule_edit_screen.dart` (신규): 전체 화면 편집
  - sport(SegmentedButton, **admin 자유 선택**), category(`Autocomplete`, 기존 카테고리 제안 + 신규 입력), title, order_idx(숫자), published(Switch)
  - body: 편집(멀티라인 TextField) ↔ 미리보기(`MarkdownBody`) **토글**(SegmentedButton/탭)
  - 저장 / 삭제(확인 다이얼로그, "보통은 게시 취소를 쓰세요" 안내) / **즉시 재계산** 버튼
- `app/lib/screens/admin/admin_screen.dart` (수정, 최소 침습): `TabController length 4→5`, `Tab('지식베이스')` 추가, `TabBarView`에 `KnowledgeBaseTab()` 추가. 기존 4탭 불변. (`isScrollable: true`라 5탭 수용)

## 검증
- `flutter analyze` + `flutter test` + `deno check embed-pending`
- admin 계정 E2E:
  1. 문서 생성 → 목록 노출, 임베딩 "대기"
  2. 즉시 재계산 → embed-pending 호출 → 잠시 후 "최신"
  3. 수정(title/body) → 다시 "대기" (트리거)로 바뀌는지 DB 확인
  4. 게시 토글 off → 앱 `rules_screen`·챗봇 RAG에서 제외
  5. 삭제(확인 다이얼로그) → 목록에서 사라짐
- 비-admin 계정에서 `rule_articles` write가 RLS로 차단되는지 (직접 supabase 호출 실패)
- 비-admin이 `embed-pending` 호출 시 거부되는지 (requireServiceRoleOrAdmin)

## 주의
- 카테고리 자유 텍스트 + 자동완성으로 오타 분산 보조 (강제는 안 함)
- 기존 `RuleArticle.fromJson` 호환 유지가 회귀 방지 핵심 — 추가 필드 nullable/기본값
- `embed-pending`은 대기 중(`embedding IS NULL`) 전체를 처리(멱등)하므로, 한 룰 재계산 요청이 다른 대기 항목도 함께 처리 — 의도된 동작
