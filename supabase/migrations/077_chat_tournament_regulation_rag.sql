-- 077: 대회 요강(regulation_*)을 채팅 RAG 에 연결
--
-- 배경:
--   regulation_fields/notes/body(요강 정형화·완전 본문)가 채팅 임베딩·시맨틱
--   검색·RAG 컨텍스트에 빠져 있어, 챗봇이 "경기방식/시상/참가자격" 같은 요강
--   질문에 답하지 못했다.
--
-- 변경:
--   1) 임베딩 무효화 트리거: regulation_fields/notes/body 변경도 감지 → 재임베딩.
--   2) tournaments_semantic_search: regulation_fields + regulation_body(절단) 반환
--      → 채팅 RAG 컨텍스트(buildContextPrompt)가 요강을 LLM 에 전달 가능.
--   (embed-pending 의 임베딩 텍스트에 regulation_body 포함, chat 컨텍스트 노출은
--    Edge Function 코드에서 처리.)

-- ── 1) 임베딩 무효화 트리거에 요강 변경 감지 추가 ──
create or replace function public.invalidate_tournament_embedding()
returns trigger language plpgsql as $$
begin
  if (old.title is distinct from new.title)
     or (old.description is distinct from new.description)
     or (old.region is distinct from new.region)
     or (old.format is distinct from new.format)
     or (old.organizer is distinct from new.organizer)
     or (old.regulation_fields is distinct from new.regulation_fields)
     or (old.regulation_notes is distinct from new.regulation_notes)
     or (old.regulation_body is distinct from new.regulation_body)
  then
    new.embedding := null;
    new.embedding_updated_at := null;
  end if;
  return new;
end;
$$;

-- ── 2) tournaments_semantic_search: 요강 반환 추가 ──
-- 반환 컬럼이 늘어나므로 DROP 후 재생성.
DROP FUNCTION IF EXISTS public.tournaments_semantic_search(uuid, vector, boolean, integer, text);

CREATE FUNCTION public.tournaments_semantic_search(
  p_user_id uuid,
  p_query_embedding vector,
  p_only_my_grade boolean DEFAULT true,
  p_match_count integer DEFAULT 10,
  p_sport text DEFAULT NULL::text
)
RETURNS TABLE(
  id uuid,
  sport sport,
  title text,
  start_date date,
  region text,
  eligible_grades text[],
  regulation_fields jsonb,
  regulation_body text,
  similarity real
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  select
    t.id,
    t.sport,
    t.title,
    t.start_date,
    t.region,
    t.eligible_grades,
    t.regulation_fields,
    -- RAG 컨텍스트 부담 완화: 요강 본문은 2500자로 절단.
    left(t.regulation_body, 2500) as regulation_body,
    (1 - (t.embedding <=> p_query_embedding))::real as similarity
  from public.tournaments t
  where t.status = 'published'
    and t.embedding is not null
    and (p_sport is null or t.sport::text = p_sport)
    and (
      not p_only_my_grade
      or (t.sport = 'tennis' and exists (
        select 1 from public.user_tennis_orgs uto
        where uto.user_id = p_user_id
          and uto.division_codes && t.eligible_grades
      ))
      or (t.sport = 'tennis'
        and exists (
          select 1 from public.user_sports us
          where us.user_id = p_user_id and us.sport = 'tennis'
        )
        and not exists (
          select 1 from public.user_tennis_orgs uto
          where uto.user_id = p_user_id
        )
      )
      or (t.sport != 'tennis' and exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      ))
    )
  order by t.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$function$;
