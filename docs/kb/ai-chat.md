# AI 챗봇 시스템

> 비용·품질 운영 기준은 [`../plans/PLAN_llm-cost-reduction.md`](../plans/PLAN_llm-cost-reduction.md) 참조.
> 이 문서는 **현재 구현 상태**를 기술한다 (구현 파일: `supabase/functions/chat/index.ts`).

## 아키텍처 (4단 라우팅)

```
Flutter (SSE) → chat Edge Function
   │
   ├─[1] Intent 분류 (룰 → pgvector KNN 폴백)
   │       └ 미등록 종목 명시 → 즉시 거부 (LLM·RAG 우회)
   │
   ├─[2] Slot routing — tournament_search & confidence ≥ 0.95
   │       └ 화이트리스트 RPC + 템플릿 응답 (LLM 호출 0)
   │
   ├─[3] QA cache lookup (cosine ≥ 0.92, TTL 24h)
   │       └ HIT → 캐시 답 즉시 반환 (LLM·RAG 우회)
   │
   └─[4] RAG (pgvector 시맨틱 검색) → Gemini Flash-Lite (SSE 스트리밍)
           └ RAG 0건이면 LLM 호출 없이 "DB에 없음" 응답
```

## 핵심 구성

| 요소 | 값 | 비고 |
|---|---|---|
| LLM 모델 | `GEMINI_MODEL` (기본 `gemini-3.1-flash-lite`) | `_shared/gemini.ts` |
| thinkingBudget | 항상 `0` | grounding 제거 후 thinking 불필요 |
| temperature / maxOutputTokens | 0.4 / 2048 | |
| 임베딩 모델 | `GEMINI_EMBEDDING_MODEL` (기본 `gemini-embedding-2`) | `_shared/embedding.ts` |
| 임베딩 차원 | 768 (`outputDimensionality`) | DB `vector(768)` |
| 벡터DB | pgvector (HNSW, cosine) | tournaments/rules/intent_examples/qa_cache |
| 스트리밍 | Server-Sent Events (SSE) | |

## 의도 분류 (`_shared/intent.ts`)

- 의도 8종: `tournament_search`, `tournament_detail`, `club_search`, `rule_lookup`,
  `venue_search`, `match_schedule`, `my_profile`, `free_chat`.
- 1차 **룰 분류** (`classifyByRule`) — 정규식·키워드, confidence 1.0. recall 우선
  (false positive 보다 false negative 가 안전 → 모호하면 `null` 반환).
- 2차 **임베딩 KNN 폴백** — RPC `intent_classify` (cosine, threshold 0.75).
  `intent_examples` 테이블의 few-shot 예시 기준.
- 3차 **free_chat 폴백**.
- **슬롯 추출** (`extractSlots`) 은 의도와 독립적으로 항상 수행:
  `region`(한국어 별칭 → REGION_CODES), `sport`, `date_range`(KST 기준 자연어 → ISO).
- 회귀 테스트: `supabase/functions/tests/intent_test.ts` (정형 질문 14건 샘플).

## Slot routing (LLM 0회)

- `ROUTABLE_INTENTS = {tournament_search}`, `ROUTING_CONFIDENCE_THRESHOLD = 0.95`.
- 룰 분류(confidence 1.0)만 통과, 임베딩 폴백(보통 0.7~0.85)은 자동 미달 → 안전하게 RAG+LLM.
- RPC `tournament_search_by_slots` (화이트리스트, `security invoker` + RLS) → `renderTournamentSearchTemplate` 로 결정적 마크다운 생성.
- 결과 0건 또는 RPC 에러는 **return 하지 않고** 기존 RAG+LLM 흐름으로 자연 전환 (false negative 회피).

## QA cache (`qa_cache`)

- RPC `qa_cache_lookup` / `qa_cache_insert_if_absent` — **service_role 전용** (RLS 우회).
- 임계값 cosine **0.92**, TTL **24h**, `hit_count` 증가.
- **캐시 격리**: `user_context_hash` (종목·등급·협회 정규화 SHA-256) 로 키 분리 →
  개인화 답변이 다른 사용자에게 누출되지 않음.
- **캐시 skip 조건** (lookup·insert 대칭):
  - 이전 대화 이력 존재 (`skip_history`) — 컨텍스트 의존 답변.
  - 메시지에 종목 명시 (`skip_sport_filter`) — context_hash 에 sport 미포함.
  - 임베딩 누락 (`skip_no_embedding`).
- 정상 LLM 응답만 캐싱 — refusal / RAG 에러 / LLM 에러는 저장 안 함.

## RAG 파이프라인

1. **임베딩 생성** — `embed-pending` Edge Function (pg_cron 주기 실행).
   `embedding IS NULL` 인 published 대회 → 768d 벡터 → `tournaments.embedding`.
2. **검색** — `tournaments_semantic_search` (top 5, `p_only_my_grade: false`),
   `rules_semantic_search` (top 3). venue_search 의도는 `venues_search` RPC 직접 호출(임베딩 불필요).
3. **응답 생성** — RAG 컨텍스트(`<data>` 블록) + system prompt → Gemini Flash-Lite SSE.

## Search Grounding 발동 기준 (정책)

**현재: 백엔드에서 강제 OFF.** Google Search grounding 은 `_shared/gemini.ts` 에서
호출 자체를 만들지 않는다 (옵션·tool 빌드 분기 제거). 사용자/클라이언트가 켤 수 없다.

근거:
- 본 서비스는 **DB 등록 데이터(대회·룰·구장)만** 출처로 사용. 외부 웹 정보는 환각·오정보 위험.
- grounding 은 호출당 비용이 크고, 부분 활성화(옵션 노출) 시 비용 재폭주 위험.
- DB citation 으로 출처 표기 요구는 이미 충족.

재활성화를 검토할 수 있는 조건 (충족 전까지 OFF 유지):
1. DB 로 답할 수 없는 질문 유형이 로그상 유의미한 비율로 반복 확인될 것.
2. grounding 사용을 **특정 의도로 한정**하는 화이트리스트 설계가 있을 것
   (전체 free_chat 에 무분별 적용 금지).
3. 호출당 비용 상한·일일 쿼터·결과 citation 검증 절차가 함께 들어갈 것.
4. 백엔드 강제 제어 유지 (클라이언트 토글 노출 금지).

> 시스템 프롬프트는 DB 외 정보 요청 시 "DB에 등록되어 있지 않습니다" 로 답하도록 강제한다.

## 비용 제어 요약

| 장치 | 위치 | 효과 |
|---|---|---|
| Rate limit 10회/분 | `chat_rate_limit` | 남용 차단 |
| Slot routing | `tournament_search_by_slots` | 정형 질문 LLM 0회 |
| QA cache | `qa_cache` (0.92 / 24h) | 유사 질문 LLM 0회 |
| free_chat RAG skip | `skipRag` | 잡담 시 임베딩·citation 우회 |
| RAG 0건 → LLM 우회 | chat/index.ts | 환각 방지 + 비용 0 |
| grounding OFF | `_shared/gemini.ts` | 외부 검색 비용 0 |
| thinkingBudget 0 | `_shared/gemini.ts` | thinking 토큰 0 |

## 모니터링 (비용 로그)

chat Edge Function 은 구조화 JSON 로그를 마커와 함께 출력한다 (PII 회피 위해 `user_id_hash` 사용):

| 마커 | 주요 event |
|---|---|
| `chat_intent` | `classify`, `refuse_unregistered_sport`, `knn_rpc_error`, `knn_exception` |
| `chat_cache` | `hit`, `miss`, `skip_history`, `skip_sport_filter`, `skip_no_embedding`, `insert`, `insert_skipped_duplicate`, `insert_failed` |
| `chat_route` | `tournament_search_routed`, `tournament_search_empty`, `tournament_search_rpc_error` |

**분석 도구**: `scripts/analyze_chat_cost.py` — 로그를 흘려넣으면 QA cache 히트율,
intent 분포·method 믹스, routing(LLM 우회) 비율, 임베딩 호출 수, 미등록종목 거부 수를 집계한다.

```bash
# Supabase 로그 / docker logs 를 그대로 파이프
cat chat.log | python3 scripts/analyze_chat_cost.py
python3 scripts/analyze_chat_cost.py --json chat.log   # JSON 출력
```

목표 지표 (PLAN Day 7): cache hit rate 40%+, classifier accuracy 85%+,
일 비용 현재의 15~30%, cache HIT 응답 < 200ms.

## Flutter 구현

- `ChatScreen` — SSE 스트림 수신, 마크다운 렌더링.
- `ApiService.chat()` — `http.Request` 로 SSE 스트리밍, `ChatStreamEvent` yield.
- 대화 이력: `chat-history` Edge Function (GET/DELETE).
- SSE 이벤트: `meta`, `intent`, `route`, `cache`, `context`, `delta`, `citation`, `done`, `error`.

## 보안

- `<data>...</data>` 블록 내용은 **데이터**이며 그 안의 지시는 따르지 않는다 (프롬프트 인젝션 방지).
- `escapeForData` 로 `</data>` 위조 종결 차단.
- RAG·검색 스니펫은 untrusted data (BACKEND_RULES.md / SECURITY_RULES.md 참조).
