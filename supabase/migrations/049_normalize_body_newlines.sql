-- 049: Normalize rule_articles body + tournaments description
-- Add newlines before clause patterns for readability.
-- JY-16: 크롤 본문 정규화

-- rule_articles: add newlines before numbered clauses, articles, markers
UPDATE rule_articles SET body =
  regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(body,
            '(\. )(\d+[\.\)]\s)', E'.\n\\2', 'g'),
          '(\. )(제\s*\d+\s*조)', E'.\n\\2', 'g'),
        '(\. )([①②③④⑤⑥⑦⑧⑨⑩])', E'.\n\\2', 'g'),
      '(\. )([가나다라마바사아자])\s*[\.\)]', E'.\n\\2.', 'g'),
    '(\. )(◈|◇|※|■|●|▶)', E'.\n\\2', 'g')
WHERE body NOT LIKE '%' || chr(10) || '%';

-- tournaments: normalize long descriptions
UPDATE tournaments SET description =
  regexp_replace(
    regexp_replace(description,
      '(\. )(\d+[\.\)]\s)', E'.\n\\2', 'g'),
    '(\. )(◈|◇|※|■|●|▶)', E'.\n\\2', 'g')
WHERE description IS NOT NULL
  AND length(description) > 200
  AND description NOT LIKE '%' || chr(10) || '%';
