# LLM 챗봇 비용 최적화 — 2026년 업계 트렌드 조사

생성: 2026-05-20
범위: 매치업 채팅 비용 폭주 원인 분석 / 2026 업계 패턴 6종 검토 / 한국어 모델 비교 / 권장 아키텍처
관련 계획: [`../plans/PLAN_llm-cost-reduction.md`](../plans/PLAN_llm-cost-reduction.md)

## 목차

- [Executive Summary](#executive-summary) — 한 페이지로
- [Part A. 배경 — 현재 비용 구조](#part-a-배경--현재-비용-구조)
- [Part B. 가격 분석 (Gemini 2026-05 기준)](#part-b-가격-분석-gemini-2026-05-기준)
- [Part C. 2026 업계 패턴 6종](#part-c-2026-업계-패턴-6종)
- [Part D. 한국어 모델 비교](#part-d-한국어-모델-비교)
- [Part E. 권장 아키텍처 (4단 라우팅)](#part-e-권장-아키텍처-4단-라우팅)
- [출처](#출처)

---

## Executive Summary

### 1. 가장 큰 문제 — 모든 채팅이 Flagship + Grounding

`supabase/functions/chat/index.ts:272` 에서 `enableSearch: body.enable_search ?? true` 로 기본값이 켜져 있어, 사용자 질문 전부가 **gemini-2.5-flash + Google Search grounding** 으로 처리됨. 결과: 며칠 만에 $8 청구, Google AI Studio **월간 spend cap 도달**.

→ 매치업 데이터(토너먼트·클럽)는 **이미 Postgres DB 에 적재**되어 있어 외부 grounding 이 본질적으로 불필요.

### 2. 사용자 질문 분포 (추정)

| 유형 | 비중 | 처리 비용 (현재) | 적정 처리 비용 |
|------|------|-----------------|---------------|
| 정형 (지역별 대회·클럽·매치 일정) | 70-80% | $0.035 + LLM | **$0** (SQL + 템플릿) |
| 자유형 (규정·매너·조언) | 20-30% | $0.035 + LLM | LLM-Lite 1회 |

### 3. 핵심 결론

- **즉시(Day 1)**: 모델을 `gemini-2.5-flash-lite` 로, `enableSearch=false` 강제 → 단가 **6.25배 절감** + grounding 비용 0
- **단기(Day 2-7)**: Semantic cache + Intent classifier + Text-to-SQL → 추가 **30-50% 절감**
- **누적 예상 절감**: **70-85%**
- **품질**: Flash-Lite 는 RAG/템플릿 답변 충분 (한국어 leaderboard 기준 동일 티어 GPT-4o-mini 와 동급)

### 4. 피해야 할 선택지

| 안티패턴 | 이유 |
|---------|------|
| self-host Llama 1B / Gemma 2B | Supabase Edge (Deno) 콜드 스타트·CPU 한계로 비현실적 |
| 라우터로 또 다른 LLM 호출 | 라우터 단가 > 본 모델 절감액 |
| 정형 질문 무기한 캐싱 | 토너먼트 일정 변동 → 오답 |
| LLM 임의 SQL 실행 | injection·권한 escalation 위험 |
| 의도 카테고리 조합 폭증 | 지역×날짜×종목 별 의도화 금지 — 슬롯 추출로 분리 |
| ColBERT / Qdrant 인프라 추가 | 현 단계 오버엔지니어링 |

---

# Part A. 배경 — 현재 비용 구조

## A.1 현재 호출 경로

```
사용자 메시지
  └─→ chat/index.ts:272
       └─→ enableSearch: true (디폴트)
            └─→ Gemini 2.5 Flash + tools: [{googleSearch: {}}]
                 └─→ 매 요청 grounding 비용 + thinking 토큰 비용
```

## A.2 데이터 소스 실제 위치

크롤링한 토너먼트·클럽·매치 데이터는 **이미 Postgres DB 에 저장**되어 있음. 외부 검색이 채워주는 정보의 90% 이상이 이미 내부에 존재하거나, 내부 데이터로 답하면 충분한 질문임.

## A.3 사용자 질문 유형 (추정)

- **70-80% 정형**: "강남구 5월 24일 토너먼트", "동탄 풋살 클럽", "이번 주말 매치 일정"
- **20-30% 자유형**: "셀프콜 규정 어떻게 돼?", "초보가 어느 협회로 가야 해?"

정형 질문은 **LLM 자체가 불필요** — SQL + 템플릿이면 충분.

---

# Part B. 가격 분석 (Gemini 2026-05 기준)

출처: [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) (2026-05-20 확인)

## B.1 토큰 단가

| 모델 | Input ($/1M) | Output ($/1M) | 비고 |
|------|-------------|---------------|------|
| **gemini-2.5-flash** | $0.30 | $2.50 | thinking 토큰 포함 |
| **gemini-2.5-flash-lite** | $0.10 | $0.40 | 비교 기준 |
| gemini-2.0-flash | $0.10 | $0.40 | **공급자 deprecation 공지 기준, Earliest February 2026 — 출처 확인 필요** ([Gemini API Deprecations](https://ai.google.dev/gemini-api/docs/deprecations)) |

→ **Flash → Flash-Lite 전환만으로 input 3배, output 6.25배 절감**.

## B.2 Google Search Grounding 추가 비용

| 항목 | 금액 |
|------|------|
| 일반 Gemini API 무료 quota | **1,500 RPD** |
| **Grounding with Google Search 별도 무료 quota** | **500 RPD** (일반 quota 와 분리) |
| Grounding 초과 시 | **$35 per 1,000 grounded prompts** ($0.035/요청) |

출처: [Gemini API Pricing — Google AI Studio](https://ai.google.dev/gemini-api/docs/pricing) (2026-05-20 확인)

매치업처럼 모든 채팅에 grounding 을 켜면, 1,500 RPD 를 며칠 만에 소진하고 이후 요청 1건당 $0.035 가 토큰 비용과 별개로 부과됨. 일 5,000 요청이면 grounding 만으로 약 (5000−1500)×$0.035 = **$122.5/일**.

---

# Part C. 2026 업계 패턴 6종

## C.1 Cascading / Routing

- **RouteLLM** (LMSYS, 2024-07): MT-Bench 에서 GPT-4 대비 **85% 비용 절감, 95% 품질 유지** 보고
- **2026 production 현실**: RouteLLM 같은 라우터 LLM 보다 **LiteLLM / Bifrost / Portkey** 같은 게이트웨이 룰 기반 라우팅이 더 일반적 (운영 비용·복잡도 낮음)
- **안티패턴**: 라우터로 또 다른 LLM 을 호출하면 절감액보다 라우터 단가가 더 큰 경우가 잦음

→ 매치업 적용: **룰 기반 1차 분류 + 임베딩 fallback** 으로 충분, 라우터 LLM 호출 0회.

## C.2 Semantic Cache

- **Production hit rate 평균 20-45%**, FAQ 강한 도메인은 60%+
- **VentureBeat 사례**: text-cache 18% → semantic-cache 67%, **API 비용 73% 감소**
- **GPT Semantic Cache** (arXiv 2411.05276): 8,000 QA pair 에서 **API 호출 68.8% 감소, 매칭 정확도 97%**
- **Deno/Supabase 환경 권장**: `GPTCache` 는 Python 전용 → **pgvector + cosine similarity 자가 구현** 권장 (인프라 추가 0)

→ 매치업 예상 hit rate: **40-60%** (자유형 질문 패턴이 좁음).

## C.3 Intent Classification 우선 라우팅

- **2026 표준**: 룰 + 작은 분류기 → LLM 은 fallback
- 매치업 의도 카테고리는 **10개 미만**으로 명확 (`tournament_search`, `club_search`, `match_schedule`, `rule_lookup`, `free_chat` ...)
- **안티패턴**: 의도 카테고리 폭증 — 지역/날짜/종목 조합별로 별개 의도를 만들면 안 됨. **슬롯 추출**로 분리.

→ 매치업 적용: 정규식 + 키워드 → pgvector KNN fallback.

## C.4 Small LM for routing (Edge runtime)

- Llama 3.2 1B / Gemma 2 2B: edge device 적합하나 **Supabase Edge (Deno) 에 비현실적**
  - 콜드 스타트 초 단위, CPU/메모리 제한, GPU 없음
- **권장**: `gemini-2.5-flash-lite` 자체를 small router 로 사용 ($0.10 input)

→ 매치업 적용: self-host 시도 금지, Flash-Lite 가 사실상 small router 역할.

## C.5 Embedding-based FAQ matching vs ColBERT

- **단일 벡터 + cosine + reranker** 가 압도적 다수 패턴
- **ColBERT v2** 도입은 오버엔지니어링 — 수천~수만 FAQ 까지는 **pgvector 단독으로 충분**
- 한국어 풀텍스트 보강: **pg_trgm 또는 Mecab-ko**

→ 매치업 적용: Supabase 내 pgvector + hnsw 인덱스로 충분, 추가 인프라 0.

## C.6 Hybrid RAG + Text-to-SQL

- **스키마 명확한 도메인에서 RAG 보다 우월** — "강남구 5월 24일 토너먼트" 류는 SQL 한 줄
- **패턴**:
  ```
  LLM → SQL 생성 (function calling)
      → SQL 실행 (read-only DB role)
      → 템플릿 렌더 (자연어 변환 생략 가능 = LLM 호출 0회)
  ```
- **보안 필수**:
  - 파라미터화 prepared statement
  - read-only DB role + RLS 적용
  - **함수 화이트리스트** — LLM 임의 SQL 금지

→ 매치업 적용: 정형 70-80% 를 여기서 흡수 = **LLM 호출 자체가 0**.

---

# Part D. 한국어 모델 비교

per 1M tokens 기준 (2026-05 확인분)

| 모델 | Input | Output | 비고 |
|------|-------|--------|------|
| **Gemini 2.5 Flash-Lite** | $0.10 | $0.40 | RAG 답변 충분, 멀티모달, Google 생태계 |
| GPT-4o-mini | $0.15 | $0.60 | 비슷한 티어, 한국어 품질 유사 |
| Claude Haiku 4.5 | $1.00 | $5.00 | 품질 우수하나 **10배+ 비용** |
| Solar Pro (Upstage) | API 별도 | API 별도 | **KMMLU 80.1**, 한국어 leaderboard 상위, 자체 호스팅 옵션 |
| HyperCLOVA-X HCX-S | NCP 가격 | NCP 가격 | 한국 특화, NCP 종속 |

**결론**: 매치업 ROI 측면 **Gemini Flash-Lite 가 최적**.
- 비용: 동급 티어 최저
- 품질: RAG/템플릿 답변에 필요한 한국어 자연스러움 충분
- 마이그레이션 비용: 0 (이미 Gemini SDK 사용 중)

Solar/HyperCLOVA 는 한국어 품질 우위지만 **API 통합·과금 체계 변경 비용**이 절감액보다 큼.

---

# Part E. 권장 아키텍처 (4단 라우팅)

## E.1 흐름도

```
사용자 질문
  │
  ├─[1] Intent Classifier (룰 + pgvector KNN)
  │      ↳ LLM 호출 0회
  │
  ├─ 정형 의도
  │      ├─[2a] Slot 추출 (지역·날짜·종목)
  │      ├─[2b] 화이트리스트 SQL 실행 (read-only)
  │      └─[2c] 템플릿 렌더 → 응답
  │            ↳ LLM 호출 0회
  │
  └─ 자유형 의도
         ├─[3] Semantic Cache lookup (pgvector, threshold 0.92)
         │      ├─ HIT (40-60% 추정 — 실제 트래픽 분포에 따라 변동, 운영 중 측정 필요) → 캐시 답
         │      │    ↳ LLM 호출 0회
         │      │
         │      └─ MISS
         │           └─[4] Gemini Flash-Lite + DB context
         │                  (context caching ON, grounding OFF)
         │                  ↳ LLM 호출 1회 (최저 단가)
         │                  └─ 응답 + 캐시 저장 (TTL 24h)
```

## E.2 각 단계 LLM 호출 수

| 단계 | LLM 호출 | 처리 비중 (예상) | 단건 비용 |
|------|---------|-----------------|----------|
| [1] Intent classify | 0 | 100% | $0 |
| [2] SQL + 템플릿 | 0 | 70-80% (정형) | $0 |
| [3] Cache HIT | 0 | 자유형 중 40-60% | $0 |
| [4] Flash-Lite fallback | 1 | 자유형 중 40-60% | ~$0.0005 |

## E.3 예상 비용 절감

- 정형 흡수 (75% × 0 비용) → 즉시 75% 절감
- 자유형 캐시 (25% × 50% × 0 비용) → 추가 12.5% 절감
- 잔여 fallback (25% × 50% × Flash-Lite 단가) → 기존 Flash 대비 6.25배 저렴
- **총 절감 예상: 70-85%**

추가로 grounding 비용 ($0.035/요청) 전면 제거.

---

## 출처

### Routing / Cascading
- [RouteLLM (GitHub)](https://github.com/lm-sys/routellm)
- [LMSYS Blog — RouteLLM](https://www.lmsys.org/blog/2024-07-01-routellm/)
- [LLM Routing & Model Cascades — Tian Pan](https://tianpan.co/blog/2025-11-03-llm-routing-model-cascades)

### Semantic Cache
- [Top Semantic Caching Solutions for AI Applications in 2026 — Maxim](https://www.getmaxim.ai/articles/top-semantic-caching-solutions-for-ai-applications-in-2026/)
- [GPT Semantic Cache — arXiv 2411.05276](https://arxiv.org/pdf/2411.05276)
- [Semantic Caching for LLM Apps — Percona](https://www.percona.com/blog/semantic-caching-for-llm-apps-reduce-costs-by-40-80-and-speed-up-by-250x/)

### 가격 / 모델
- [Gemini API Pricing (공식)](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini 2.5 Flash-Lite Pricing — Another Wrapper](https://anotherwrapper.com/tools/llm-pricing/gemini-25-flash-lite)
- [Korean LLM Leaderboard — BenchLM](https://benchlm.ai/leaderboards/korean-llm)

### Supabase / Deno Edge
- [Supabase Edge Runtime (Self-Hosted Deno)](https://supabase.com/blog/edge-runtime-self-hosted-deno-functions)
- [Supabase AI / pgvector Guide](https://supabase.com/docs/guides/ai)

### Text-to-SQL
- [LLM Text-to-SQL Architectures (GitHub)](https://github.com/arunpshankar/LLM-Text-to-SQL-Architectures)
- [LLM Text-to-SQL — K2View](https://www.k2view.com/blog/llm-text-to-sql/)
