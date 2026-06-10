# 풋살 룰북 DB 적용 및 코치봇 검색 확인 가이드

## 목적

풋살 룰북 50개 글을 `rule_articles`에 적용하고, 룰북 화면과 코치봇 검색에서 풋살 규칙이 잘 잡히도록 확인한다.

## 현재 코드에 준비된 내용

- 풋살 룰북 50개 시드: `supabase/migrations/047_seed_futsal_rules.sql`
- 풋살 룰북 카테고리 재분류: `supabase/migrations/052_recategorize_futsal_rule_articles.sql`
- 임베딩 생성 워커: `supabase/functions/embed-pending`
- 코치봇 검색: `supabase/functions/chat`에서 `rules_semantic_search` RPC를 사용

## 1. 현재 DB에 풋살 룰북이 들어갔는지 확인

Supabase Dashboard > SQL Editor에서 실행:

```sql
select
  sport,
  category,
  count(*) as article_count,
  count(*) filter (where embedding is not null) as embedded_count
from public.rule_articles
where sport = 'futsal'
group by sport, category
order by category;
```

기대값:

- `article_count` 합계가 50개 이상이면 풋살 룰북 시드가 들어간 상태
- `embedded_count`가 0이면 아직 코치봇 의미검색용 임베딩이 없는 상태
- 카테고리가 `풋살규칙`, `경기규칙서`처럼 크게만 묶여 있으면 재분류 마이그레이션이 아직 적용되지 않은 상태

전체 개수만 빠르게 확인하려면:

```sql
select
  count(*) as futsal_rule_count,
  count(*) filter (where embedding is not null) as embedded_count,
  count(*) filter (where embedding is null) as pending_embedding_count
from public.rule_articles
where sport = 'futsal'
  and published = true;
```

## 2. 풋살 룰북 50개가 없을 때 적용

아직 50개가 없다면 `047_seed_futsal_rules.sql`이 실제 DB에 적용되지 않은 상태다.

적용 방법 중 하나를 선택한다.

### 방법 A. Supabase CLI

```bash
supabase db push
```

### 방법 B. Supabase SQL Editor

`supabase/migrations/047_seed_futsal_rules.sql` 내용을 SQL Editor에 붙여넣고 실행한다.

## 3. 카테고리 재분류 적용

풋살 룰북을 앱에서 보기 좋게 묶기 위해 아래 마이그레이션을 적용한다.

파일:

```text
supabase/migrations/052_recategorize_futsal_rule_articles.sql
```

적용 후 기대 카테고리:

- 경기 진행
- 골키퍼
- 파울
- 킥인/재개
- 장비/경기장
- 포지션/전술
- 부상/컨디션
- 구장/팀원
- 연맹 안내

이 마이그레이션은 카테고리 변경 후 `embedding = null`로 만들어 임베딩 재생성 대상에 올린다.

## 4. rule_articles.embedding 생성

카테고리 재분류 후에는 임베딩이 null이므로 `embed-pending`을 실행해야 한다.

Supabase Dashboard > Edge Functions > `embed-pending`에서 Invoke 하거나, 프로젝트 함수 URL로 호출한다.

```bash
curl -X POST "https://bsjdgwmveokanclqwtvx.supabase.co/functions/v1/embed-pending"
```

주의:

- 이 함수는 배치 처리라 한 번에 전부 끝나지 않을 수 있다.
- `pending_embedding_count`가 0이 될 때까지 여러 번 실행한다.
- Gemini API 키/Edge Function secret이 Supabase에 설정되어 있어야 한다.

진행 확인 SQL:

```sql
select
  count(*) filter (where embedding is null) as pending_embedding_count,
  count(*) filter (where embedding is not null) as embedded_count
from public.rule_articles
where sport = 'futsal'
  and published = true;
```

## 5. 코치봇 검색에 풋살 룰북이 잡히는지 확인

앱 코치봇에서 아래 질문으로 테스트한다.

```text
풋살 골키퍼 4초 제한 알려줘
```

```text
풋살 백패스는 언제 반칙이야?
```

```text
풋살 킥인은 어떻게 해?
```

```text
풋살 누적 파울 규칙 알려줘
```

정상 동작 기준:

- 답변이 풋살 규칙 위주로 나온다.
- 테니스 규칙이 섞이지 않는다.
- 관련 룰북 출처 또는 룰북 기반 설명이 나온다.

## 6. 문제별 확인

### 룰북 화면에 풋살이 비어 있음

확인:

```sql
select id, category, title, published
from public.rule_articles
where sport = 'futsal'
order by category, order_idx
limit 20;
```

### 코치봇이 풋살 규칙을 못 찾음

확인:

```sql
select title, category, embedding is not null as has_embedding
from public.rule_articles
where sport = 'futsal'
  and published = true
order by category, order_idx
limit 20;
```

`has_embedding`이 false면 `embed-pending`을 다시 실행한다.

### 답변에 테니스가 섞임

질문에 반드시 `풋살`이라는 종목명을 포함해서 테스트한다.

예:

```text
풋살에서 골키퍼가 공을 몇 초까지 잡을 수 있어?
```

코드상 코치봇은 질문에 `풋살`이 명시되면 `rules_semantic_search`에 `p_sport = futsal`을 넘겨 풋살 룰북만 검색하도록 되어 있다.
