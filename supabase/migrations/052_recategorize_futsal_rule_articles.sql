-- 052: Recategorize futsal rule articles for better rulebook navigation.
--
-- This keeps the existing 50 futsal articles but groups them into user-facing
-- categories that are easier to scan in the app. Category changes are also
-- marked for re-embedding so coachbot/RAG search can pick up the refined labels.

UPDATE public.rule_articles
SET
  category = CASE
    WHEN title ILIKE '%골키퍼%'
      OR title ILIKE '%백패스%'
      OR title ILIKE '%골 클리%'
      THEN '골키퍼'

    WHEN title ILIKE '%파울%'
      OR title ILIKE '%불법행위%'
      OR title ILIKE '%프리킥%'
      OR title ILIKE '%페널티%'
      THEN '파울'

    WHEN title ILIKE '%킥-인%'
      OR title ILIKE '%킥인%'
      OR title ILIKE '%코너 킥%'
      OR title ILIKE '%플레이의 시작%'
      THEN '킥인/재개'

    WHEN title ILIKE '%풋살화%'
      OR title ILIKE '%준비물%'
      OR title ILIKE '%장비%'
      OR title ILIKE '%볼'
      OR title ILIKE '%피치%'
      OR title ILIKE '%경기장%'
      THEN '장비/경기장'

    WHEN title ILIKE '%포지션%'
      OR title ILIKE '%역할%'
      OR title ILIKE '%전략%'
      OR title ILIKE '%잘하는 방법%'
      THEN '포지션/전술'

    WHEN title ILIKE '%부상%'
      OR title ILIKE '%근육통%'
      OR title ILIKE '%발톱%'
      OR title ILIKE '%상처%'
      OR title ILIKE '%발목%'
      OR title ILIKE '%식사%'
      OR title ILIKE '%생리%'
      OR title ILIKE '%겨울%'
      OR title ILIKE '%운동 추천%'
      THEN '부상/컨디션'

    WHEN title ILIKE '%연맹%'
      OR title ILIKE '%FK리그%'
      OR title ILIKE '%출처%'
      OR category ILIKE '%연맹%'
      THEN '연맹 안내'

    WHEN title ILIKE '%친구%'
      OR title ILIKE '%구장%'
      OR title ILIKE '%대관%'
      OR title ILIKE '%구매사이트%'
      THEN '구장/팀원'

    ELSE '경기 진행'
  END,
  embedding = NULL,
  embedding_updated_at = NULL
WHERE sport = 'futsal'
  AND published = TRUE
  AND (
    category IN ('풋살규칙', '한국풋살연맹', '경기규칙서', '풋살연맹안내')
    OR title ILIKE '%풋살%'
    OR title ILIKE '규칙 %'
  );
