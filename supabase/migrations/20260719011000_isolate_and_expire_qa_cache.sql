-- The original semantic cache was shared by users with the same sports/org
-- profile and stored raw questions/answers. Remove those ambiguous rows, bind
-- every future row to one account, and physically delete expired data daily.

TRUNCATE TABLE public.qa_cache;

ALTER TABLE public.qa_cache
  ADD COLUMN owner_user_id uuid REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.qa_cache
  ALTER COLUMN owner_user_id SET NOT NULL;

DROP INDEX IF EXISTS public.qa_cache_unique_question_per_context;
CREATE UNIQUE INDEX qa_cache_unique_question_per_user_context
  ON public.qa_cache (owner_user_id, user_context_hash, md5(question_text));

DROP FUNCTION IF EXISTS public.qa_cache_lookup(public.vector, text, real);
CREATE FUNCTION public.qa_cache_lookup(
  p_query_embedding public.vector(768),
  p_owner_user_id uuid,
  p_user_context_hash text,
  p_threshold real DEFAULT 0.92
)
RETURNS TABLE (
  id uuid,
  answer_text text,
  citations jsonb,
  similarity real
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    cache.id,
    cache.answer_text,
    cache.citations,
    (
      1 - (
        cache.question_embedding OPERATOR(public.<=>) p_query_embedding
      )
    )::real AS similarity
  FROM public.qa_cache AS cache
  WHERE cache.owner_user_id = p_owner_user_id
    AND cache.user_context_hash = p_user_context_hash
    AND cache.ttl_expires_at > now()
    AND (
      1 - (
        cache.question_embedding OPERATOR(public.<=>) p_query_embedding
      )
    ) >= p_threshold
  ORDER BY cache.question_embedding OPERATOR(public.<=>) p_query_embedding
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.qa_cache_lookup(
  public.vector,
  uuid,
  text,
  real
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.qa_cache_lookup(
  public.vector,
  uuid,
  text,
  real
) TO service_role;

DROP FUNCTION IF EXISTS public.qa_cache_insert_if_absent(
  text,
  public.vector,
  text,
  jsonb,
  text,
  timestamptz
);
CREATE FUNCTION public.qa_cache_insert_if_absent(
  p_owner_user_id uuid,
  p_question_text text,
  p_question_embedding public.vector(768),
  p_answer_text text,
  p_citations jsonb,
  p_user_context_hash text,
  p_ttl_expires_at timestamptz
)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$
  INSERT INTO public.qa_cache (
    owner_user_id,
    question_text,
    question_embedding,
    answer_text,
    citations,
    user_context_hash,
    ttl_expires_at
  )
  VALUES (
    p_owner_user_id,
    p_question_text,
    p_question_embedding,
    p_answer_text,
    p_citations,
    p_user_context_hash,
    p_ttl_expires_at
  )
  ON CONFLICT (owner_user_id, user_context_hash, md5(question_text))
    DO NOTHING
  RETURNING id;
$function$;

REVOKE ALL ON FUNCTION public.qa_cache_insert_if_absent(
  uuid,
  text,
  public.vector,
  text,
  jsonb,
  text,
  timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.qa_cache_insert_if_absent(
  uuid,
  text,
  public.vector,
  text,
  jsonb,
  text,
  timestamptz
) TO service_role;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'qa-cache-expired-cleanup';

SELECT cron.schedule(
  'qa-cache-expired-cleanup',
  '15 18 * * *',
  $cron$DELETE FROM public.qa_cache WHERE ttl_expires_at <= now();$cron$
);

NOTIFY pgrst, 'reload schema';
