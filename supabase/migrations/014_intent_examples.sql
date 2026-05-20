-- 014_intent_examples.sql
-- Intent classifier (Day 3-4, LLM 비용 절감 계획).
--
-- 사용자 채팅 메시지의 의도(intent)를 분류하기 위한 예시(prompt) 임베딩 저장소.
--   - 룰 기반 1차 분류로 잡지 못한 메시지에 대해 KNN (cosine) 으로 다수결.
--   - shadow mode (Day 3-4): 분류 결과는 메트릭/SSE 이벤트로만 발송, 실제 routing 은 안 함.
--   - Day 5-6 에서 의도별 SQL+템플릿 routing 활성화 예정.
--
-- Edge Function (`chat/index.ts`) 가 service_role 키로만 조회/적재한다.
-- 임베딩은 `text-embedding-004` / `gemini-embedding-001` (outputDimensionality=768) 기준.

create extension if not exists vector;

create table if not exists public.intent_examples (
  id uuid primary key default gen_random_uuid(),

  -- 분류 라벨. chat/_shared/intent.ts 의 Intent 유니온과 동기 유지.
  -- 카테고리 추가/제거 시 양쪽 동시 변경 필요.
  intent text not null check (
    intent in (
      'tournament_search',
      'tournament_detail',
      'club_search',
      'rule_lookup',
      'match_schedule',
      'my_profile',
      'free_chat'
    )
  ),

  -- 예시 질문 원본 (디버깅/시드 식별용)
  example_text text not null,

  -- gemini-embedding-001 (outputDimensionality=768, RETRIEVAL_QUERY task) 기준
  embedding vector(768) not null,

  created_at timestamptz not null default now()
);

comment on table public.intent_examples is
  'Few-shot intent examples for chat intent classifier. service_role only (Edge Function 전용).';
comment on column public.intent_examples.intent is
  '분류 라벨. chat/_shared/intent.ts 의 Intent 유니온과 동기. 카테고리 변경 시 양쪽 동시 수정.';

-- HNSW 인덱스 (cosine). intent_examples 행은 항상 embedding not null 이므로 partial 조건 불필요.
create index if not exists intent_examples_embedding_hnsw_idx
  on public.intent_examples using hnsw (embedding vector_cosine_ops);

-- intent 별 빠른 카운트/조회용
create index if not exists intent_examples_intent_idx
  on public.intent_examples (intent);

-- =========================
-- RLS
-- =========================
alter table public.intent_examples enable row level security;

-- service_role 만 전권. anon/authenticated 직접 접근 불가.
drop policy if exists intent_examples_service_role_all on public.intent_examples;
create policy intent_examples_service_role_all on public.intent_examples
  for all
  to service_role
  using (true)
  with check (true);

-- =========================
-- RPC: intent_classify (K-NN 다수결)
-- =========================
-- intent_examples 에서 cosine similarity 상위 K개 (K=3) 를 뽑아 가장 많이 등장한 intent 를 반환.
--   - 임계값 (p_threshold) 미달 시 빈 결과 반환 → 호출 측은 free_chat 으로 폴백.
--   - 동률 시 가장 유사한 예시의 intent 우선 (count desc, avg_similarity desc).
--   - 반환: 단일 행 (intent text, similarity real). similarity 는 다수결 그룹의 평균 cosine.
--
-- 보안:
--   - security definer + service_role 만 EXECUTE 권한.
--   - 입력은 vector / real 만 받으므로 SQL injection 표면 없음.
create or replace function public.intent_classify(
  p_query_embedding vector(768),
  p_threshold real default 0.75
)
returns table (
  intent text,
  similarity real
)
language sql
stable
security definer
set search_path = public
as $$
  with knn as (
    select
      e.intent,
      (1 - (e.embedding <=> p_query_embedding))::real as sim
    from public.intent_examples e
    order by e.embedding <=> p_query_embedding
    limit 3
  ),
  filtered as (
    select intent, sim from knn where sim >= p_threshold
  ),
  agg as (
    select
      intent,
      count(*) as cnt,
      avg(sim)::real as avg_sim,
      max(sim)::real as max_sim
    from filtered
    group by intent
  )
  select intent, avg_sim as similarity
  from agg
  order by cnt desc, avg_sim desc, max_sim desc
  limit 1;
$$;

revoke all on function public.intent_classify(vector, real) from public;
grant execute on function public.intent_classify(vector, real) to service_role;

-- =========================
-- 시드 데이터 안내
-- =========================
-- 시드 INSERT 는 embedding 생성 (Gemini API 호출) 이 필요하므로 마이그레이션에 포함하지 않음.
-- 별도 스크립트로 의도별 5-10개 예시를 임베딩 후 INSERT 할 것 (Day 4 작업).
-- 시드 부재 시: intent_classify 가 항상 빈 결과 반환 → 룰 기반 1차 분류만 동작 + 미매치는 free_chat 폴백.
-- shadow mode 운영에는 룰 기반만으로도 분포/메트릭 수집 가능.
