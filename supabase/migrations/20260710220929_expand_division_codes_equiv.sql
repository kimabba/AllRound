-- 085: P2 매칭 일반화 — expand_gj_jn_codes 하드코딩 gj↔jn 치환을
--      tennis_divisions.equiv_group 사전 조회로 재구현.
--      시그니처 불변 → 6개 RPC(072/075/076/078/079/084) 무손상.
--      비파괴: 라이브 데이터 동등성 사전 확인(유저코드·대회등급 전부 사전 존재).

-- 신규 정식 함수: equiv_group 기반 확장
CREATE OR REPLACE FUNCTION public.expand_division_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT c), '{}')
  FROM (
    -- 원본 코드 pass-through (사전 미존재/equiv 없음도 자기 자신 유지)
    SELECT unnest(codes) AS c
    UNION
    -- 같은 equiv_group 형제 코드
    SELECT sib.code
    FROM unnest(codes) AS input_code
    JOIN public.tennis_divisions d   ON d.code = input_code AND d.equiv_group IS NOT NULL
    JOIN public.tennis_divisions sib ON sib.equiv_group = d.equiv_group
  ) sub
  WHERE c IS NOT NULL;
$$;

-- 별칭 재정의: 하드코딩 gj↔jn 치환 제거, IMMUTABLE→STABLE
CREATE OR REPLACE FUNCTION public.expand_gj_jn_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$ SELECT public.expand_division_codes(codes); $$;

NOTIFY pgrst, 'reload schema';
