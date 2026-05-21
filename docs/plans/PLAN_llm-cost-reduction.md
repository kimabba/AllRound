# LLM 비용 절감 실행 계획 v1

**Feature**: LLM Cost Reduction
**Scope**: Medium (7 days, 4 단계)
**Approach**: 즉시 절감 (모델 다운그레이드 + grounding off) → Semantic cache → Intent classifier → Text-to-SQL
**관련 리서치**: [`../research/llm-cost-optimization-2026.md`](../research/llm-cost-optimization-2026.md)

---

## 목표

- 현재 월 비용의 **15-30% 수준**으로 (70-85% 절감)
- **DB 데이터만으로 운영**, 외부 검색(Google Search grounding) 의존 제거
- **한국어 응답 품질 유지** (Flash-Lite 가 RAG/템플릿 답변에 충분)

## 비목표 (out of scope)

- 자체 모델 호스팅 (Llama/Gemma 등) — Deno Edge 부적합
- ColBERT/Qdrant 등 추가 벡터 인프라 도입 — pgvector 로 충분
- 다국어 확장 — 한국어 단일
- 채팅 UI 개편 — 백엔드만

---

## 아키텍처 (4단 라우팅)

```
사용자 질문
  │
  ├─[1] Intent Classifier (룰 + pgvector KNN)        ← Day 3-4
  │
  ├─ 정형 → Slot 추출 → 화이트리스트 SQL → 템플릿     ← Day 5-6
  │                                              (LLM 호출 0회)
  │
  └─ 자유형 → [2] Semantic Cache (threshold 0.92)     ← Day 2
              ├─ HIT (40-60% 추정) → 캐시 답
              └─ MISS → [3] Gemini Flash-Lite + DB context  ← Day 1
                              (grounding OFF, context caching 는 Day 7 이후 검토)
```

---

## 영향 받는 파일

| 파일 | 변경 내용 | Day |
|------|----------|-----|
| `supabase/functions/.env` | `GEMINI_MODEL=gemini-2.5-flash-lite` | 1 |
| `supabase/functions/chat/index.ts` | `enableSearch` 옵션 제거 (항상 false) | 1 |
| `supabase/functions/_shared/gemini.ts` | `googleSearch` tool 빌드 분기·grounding citation 처리 제거, `thinkingConfig` 단순화 | 1 |
| `supabase/migrations/<ts>_qa_cache.sql` | `qa_cache` 테이블 + hnsw 인덱스 | 2 |
| `supabase/functions/chat/index.ts` | 캐시 lookup 추가 | 2 |
| `supabase/migrations/<ts>_intent_examples.sql` | `intent_examples` 테이블 + 시드 | 3 |
| `supabase/functions/chat/_intent.ts` (신규) | 룰 + KNN 분류기 | 3-4 |
| `supabase/functions/chat/_sql_templates.ts` (신규) | 의도별 SQL + 템플릿 화이트리스트 | 5-6 |

DB citation 처리(내부 데이터 출처 표시)는 **유지** — Search grounding citation 만 제거.

---

## Day 별 작업

### Day 1 — 즉시 절감 (예상 효과 80%+)

**Goal**: 모델 다운그레이드 + grounding 비활성화 만으로 즉시 비용 폭주 차단

- [ ] `.env` 의 `GEMINI_MODEL` → `gemini-2.5-flash-lite`
- [ ] `chat/index.ts:272` 에서 `enableSearch` 옵션 제거 (항상 false 로 전달)
- [ ] `_shared/gemini.ts` 의 `enableSearch` 파라미터, `googleSearch` tool 빌드 분기, grounding citation 후처리 제거 (**DB citation 은 유지**)
- [ ] `_shared/gemini.ts` 의 `thinkingConfig` 단순화 — 항상 `{ thinkingBudget: 0 }`
- [ ] 백엔드 재시작 + 수동 채팅 테스트
  - 정상 케이스: "강남구 테니스 토너먼트" → DB 답변
  - 외부 정보 케이스: "광주 테니스 협회 협회장은?" → "DB에 정보 없음" 응답되어야 함
- [ ] 새 API 키 발급 + `.env` 갱신 (이전 키 회전 권장 — **노출 이력 있음**)
- [ ] Google Cloud Billing 일별 추적 시작

**Quality Gate**: 채팅 응답 정상 + Google Cloud Billing 익일 사용량 급감 확인

> **참고**: Day 1 변경은 LLM 호출 비용 (input/output) 만 절감함. Embedding 호출 (`text-embedding-004`, $0.025/1M input tokens) 은 `supabase/functions/chat/index.ts` 약 210-214 라인에서 매 채팅 요청마다 계속 발생함 — Day 3-4 Intent classifier 도입 시 정형 의도로 분류된 요청은 embedding 우회 가능 (RAG 미사용).

---

### Day 2 — Semantic Cache (예상 효과 추가 30-50%)

**Goal**: 자유형 질문 캐시로 LLM 호출 자체를 회피

- [ ] 마이그레이션 작성: `qa_cache` 테이블
  ```
  - id uuid pk
  - question_text text
  - embedding vector(768)
  - answer_text text
  - hit_count int default 0
  - ttl_expires_at timestamptz
  - user_context_hash text  -- 사용자 컨텍스트 분리용
  - created_at, updated_at
  ```
- [ ] pgvector 인덱스 (**hnsw 권장**, cosine ops)
- [ ] `chat/index.ts` 에 캐시 lookup 추가 (**threshold 0.92**)
- [ ] **정형 질문 캐싱 금지** — 동적 데이터 의존 시 skip 플래그
- [ ] **TTL 24h** + hit_count 증가 + 메트릭 로그
- [ ] 마이그레이션에 `ALTER TABLE qa_cache ENABLE ROW LEVEL SECURITY` 포함
- [ ] 정책 명시: SELECT/INSERT 는 `service_role` 만 (Edge Function 이 캐시 lookup/저장 담당), 사용자 직접 접근 차단
- [ ] `user_context_hash` 컬럼은 캐시 키 격리용 (예: 사용자 종목 prefs 해시) — 다른 사용자 답변 누출 방지
- [ ] 캐시 hit/miss 메트릭 로그 시작

**Quality Gate**: 동일·유사 질문 반복 시 cache HIT, 일별 hit rate 측정 가능

---

### Day 3-4 — Intent Classifier

**Goal**: 정형/자유형 분리 + 슬롯 추출

- [ ] 의도 카테고리 정의 (**10개 미만**)
  - 예시: `tournament_search`, `club_search`, `match_schedule`, `rule_lookup`, `free_chat`, `greeting`, `feedback`
- [ ] 룰 기반 1차 분류 (정규식 + 키워드)
- [ ] 임베딩 기반 fallback (`intent_examples` 테이블 + KNN)
- [ ] 슬롯 추출 (`region`, `date`, `sport`, `division`)
  - **카테고리 폭증 금지** — 지역×날짜×종목 조합은 슬롯으로만
- [ ] 분류 정확도 측정용 라벨 데이터셋 100건 작성

**Quality Gate**: 라벨 데이터셋 기준 정확도 85%+

---

### Day 5-6 — Text-to-SQL + 템플릿

**Goal**: 정형 의도를 LLM 호출 0회로 처리

- [x] **SQL 화이트리스트** 함수 정의 — read-only DB role 로만 실행
  - [x] `tournament_search_by_slots(p_user_id, p_sport, p_region, p_date_from, p_date_to, p_only_my_grade, p_match_count)` — 018 마이그레이션
  - [ ] `clubs_by_region_sport(region, sport)` — 후속
  - [ ] `matches_upcoming(user_id)` — 후속
- [x] 의도별 응답 템플릿 (한국어, **톤 가이드 포함**) — `renderTournamentSearchTemplate`
- [x] **LLM 임의 SQL 생성 비활성화** — 미리 정의된 RPC 만 사용
- [x] 보안 체크리스트 (tournament_search 한정)
  - [x] 파라미터화 prepared statement (Supabase RPC)
  - [x] `security invoker` + `authenticated` grant (RLS 적용)
  - [x] 슬롯 값은 intent.ts 정규식 + REGION_LABELS 매핑으로 enum/타입 검증
  - [ ] 별도 read-only DB role 분리 — 후속 (현재 authenticated 의 RLS 가 published 만 노출)

#### 현재 활성화 범위 (점진적)

| 의도 | 상태 | confidence 임계값 | 활성화 PR |
|---|---|---|---|
| `tournament_search` | **active** | ≥ 0.95 | #8 (Day 5-6) |
| `tournament_detail` | shadow | — | 데이터 확보 후 |
| `club_search` | shadow | — | 후속 |
| `rule_lookup` | shadow | — | 후속 |
| `match_schedule` | shadow | — | 후속 |
| `my_profile` | shadow | — | 후속 |
| `free_chat` | shadow | — | 라우팅 불가 (자유 채팅) |

- **`ROUTABLE_INTENTS`**: `chat/index.ts` 상수. 의도 추가 시 여기 + 의도별 핸들러 + 템플릿 동시 작성.
- **`ROUTING_CONFIDENCE_THRESHOLD = 0.95`**: 룰 분류 (confidence 1.0) 는 통과, embedding 폴백 (보통 0.7-0.85) 은 자동 미달 → fallback (안전).
- **결과 0 또는 RPC 에러**: return 안 함 → 기존 RAG+LLM 흐름으로 자연 전환 → false negative 회피.
- 다음 의도 활성화 기준: shadow 로그 분포 + 정확도 검증 + slot 추출 신뢰도 ≥ 95% + 응답 템플릿 한국어 검증 통과.

**Quality Gate**: 정형 질문 10개 케이스 LLM 호출 0회로 응답 + 보안 체크리스트 통과

---

### Day 7 — 모니터링 + 튜닝

**Goal**: 메트릭 가시화 + 임계값 보정

- [ ] 메트릭 로그
  - cache hit rate (일/주)
  - classifier accuracy (샘플링)
  - LLM fallback rate
  - 일·주 비용 (Google Cloud Billing 연동)
- [ ] 임계값 튜닝
  - cache threshold (0.92 → 0.88~0.94 범위 실험)
  - classifier confidence (룰 vs KNN 경계)
- [ ] 부하 테스트 (동시 50 요청)
- [ ] 회고 + 다음 단계 결정

**Quality Gate**: 일 비용 목표(현재의 15-30%) 달성 + 응답 품질 표본 검토 통과

---

## 피해야 할 함정

| 함정 | 이유 | 대안 |
|------|------|------|
| self-host small LM (Llama 1B 등) | Deno Edge 콜드 스타트·CPU·GPU 한계 | Flash-Lite 를 small router 로 |
| 정형 질문 무기한 캐싱 | 토너먼트 일정 변동 시 오답 | 정형 캐싱 금지 또는 짧은 TTL |
| LLM 임의 SQL 실행 | injection·권한 escalation | **함수 화이트리스트 필수** |
| 의도 카테고리 폭증 | 유지보수·분류 정확도 폭락 | 슬롯 추출로 분리 |
| ColBERT/Qdrant 추가 인프라 | 운영 비용↑·복잡도↑ | pgvector 단독으로 충분 |
| 라우터로 또 다른 LLM 호출 | 절감액보다 라우터 단가 큼 | 룰 + 임베딩 KNN |
| grounding 부분 활성화 (옵션 노출) | 사용자가 켜면 비용 재폭주 | 백엔드에서 강제 false |
| **개인화 답변의 글로벌 캐시** | 사용자 위치/종목/등급 등 컨텍스트 기반 답변을 글로벌 키로 캐싱 시 **다른 사용자에게 잘못된 개인화 답 누출 위험** | `user_context_hash` 로 키 격리 또는 캐시 자체 skip |

---

## 측정 기준

| 항목 | 도구 | 빈도 |
|------|------|------|
| **비용** | Google Cloud Billing 일별 export | 일 |
| **품질** | 채팅 응답 표본 50건 수동 검토 | 주 |
| **성능** | 평균 응답 시간 (cache hit/miss 별) | 일 |
| **Cache hit rate** | `qa_cache.hit_count` 집계 | 일 |
| **Classifier accuracy** | 라벨 데이터셋 회귀 테스트 | 변경 시 |
| **LLM fallback rate** | 로그 집계 | 일 |

목표 지표:
- 일 비용: 현재의 **15-30%**
- Cache hit rate: **40%+** (자유형 기준)
- Classifier accuracy: **85%+**
- 평균 응답 시간: cache HIT < 200ms, miss < 2s

---

## Dependencies

- **Runtime**: Supabase Edge Runtime (Deno)
- **DB**: Postgres + `pgvector` extension (hnsw 인덱스용)
- **LLM**: Gemini API (`gemini-2.5-flash-lite`, `text-embedding-004`)
- **신규 추가 인프라**: 없음 — 기존 Supabase 스택 내 처리

## Limitations / Known Issues

- **Embedding 비용 잔존**: Day 1 변경만으로는 embedding 호출 비용 (`text-embedding-004`) 이 계속 발생함. Day 3-4 Intent classifier 도입 후 정형 의도에서만 우회 가능.
- **Cache hit rate 불확실**: 40-60% 는 추정치 — 실제 트래픽 분포에 따라 변동. Day 7 측정 후 임계값 재튜닝 필요.
- **Implicit context caching 절감 미보장**: Gemini implicit caching 은 자동이지만 절감 보장 없음. Explicit caching 은 별도 API (`cachedContent`) 호출 필요 — 본 계획 범위 밖.
- **정형 질문 캐싱 불가**: 토너먼트 일정 등 동적 데이터 의존 답변은 캐시 skip — hit rate 상한 제약.
- **한국어 단일**: 다국어 확장 시 cache key/embedding 모델 재설계 필요.

## Future Work (Day 7 이후)

- **Explicit context caching (cachedContent API) 도입 검토** — 시스템 프롬프트 + RAG context 안정화된 후 별도 평가
- 의도 카테고리 확장 (현재 10개 미만 → 사용 패턴 보고 점진 추가)
- Cache hit rate 가 60%+ 안정화되면 TTL 연장 (24h → 72h) 실험
- 한국어 reranker 도입 검토 (현재는 cosine similarity 단일)
- 비용/품질 대시보드 (Grafana 또는 Supabase Studio 커스텀 뷰)

## 관련 문서

- 리서치: [`../research/llm-cost-optimization-2026.md`](../research/llm-cost-optimization-2026.md)
- 백엔드 룰: [`../rules/BACKEND_RULES.md`](../rules/BACKEND_RULES.md)
- 보안 룰: [`../rules/SECURITY_RULES.md`](../rules/SECURITY_RULES.md)
