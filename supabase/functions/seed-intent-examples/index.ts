/**
 * POST /seed-intent-examples
 *
 * 의도(intent) 별 한국어 예시를 Gemini embedding 으로 임베딩한 뒤
 * `public.intent_examples` 테이블에 일괄 INSERT 한다.
 *
 * 사용 시점:
 *   - 마이그레이션 014_intent_examples.sql 적용 후 1회.
 *   - 의도 카테고리/시드 텍스트 변경 시 재실행 (멱등 — 시작 시 기존 행 전체 삭제 후 다시 INSERT).
 *
 * 보안:
 *   - service_role 또는 admin 만 호출 가능 (`requireServiceRoleOrAdmin`).
 *   - 일반 사용자 (anon/authenticated) 는 403.
 *   - 실제 INSERT 는 service_role 클라이언트로 수행 (intent_examples 테이블은 service_role 만 접근 가능).
 *
 * 비용:
 *   - 1회 실행당 임베딩 API 호출 1회 (batchEmbedContents 49건).
 *   - text-embedding-004 (= gemini-embedding-001) 가격 정책 기준 매우 저렴.
 *
 * 응답:
 *   { inserted: number, intents: Record<Intent, number> }
 */

import { corsHeaders, errorResponse, preflight } from '../_shared/cors.ts';
import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { embedBatch, toVectorLiteral } from '../_shared/embedding.ts';
import { type Intent } from '../_shared/intent.ts';

/**
 * 의도별 시드 텍스트.
 *
 * 가이드:
 *   - 각 의도 7개 (총 49개) — 다양한 표현 (대회=시합=토너먼트=컵 등 동의어 분산).
 *   - intent_classify RPC 는 KNN top-3 다수결 → 의도별 최소 3개 권장, 7개면 안전.
 *   - 너무 일반적인 문장 ("도와줘", "알려줘" 등) 은 free_chat 에만 배치.
 *
 * 변경 시:
 *   - chat/_shared/intent.ts 의 `Intent` 유니온 및 014_intent_examples.sql 의 CHECK 제약과 동기 유지.
 *   - 카테고리 추가/제거 시 3곳 동시 변경.
 */
const SEED_EXAMPLES: Record<Intent, string[]> = {
  tournament_search: [
    '이번 주말에 어떤 대회가 있어?',
    '광주 지역 토너먼트 알려줘',
    '테니스 대회 검색',
    '5월에 열리는 풋살 시합',
    '전국 대회 일정 보여줘',
    '초보자 대회 있어?',
    '내가 출전할 수 있는 컵 대회',
  ],
  tournament_detail: [
    '광주오픈 자세히 알려줘',
    '이 대회 어떻게 신청해?',
    '참가비랑 일정 좀',
    '그 토너먼트 상세 정보',
    '대회 등급 규정 어떻게 돼',
    '어디서 열려?',
    '코트 정보 알려줘',
  ],
  club_search: [
    '강남 테니스 클럽',
    '내 주변 풋살 동호회',
    '광주 테니스 클럽 추천',
    '초보 환영하는 동호회',
    '야간 운영하는 클럽',
    '젊은 사람 많은 클럽',
    '여성 회원 많은 동호회',
  ],
  rule_lookup: [
    '테니스 듀스 규칙',
    '풋살 파울 룰',
    '타이브레이크 어떻게 해',
    '복식 룰 설명해줘',
    '오프사이드 규정',
    '코트 크기 규격',
    '킥오프 룰북',
  ],
  match_schedule: [
    '오늘 매치 있어?',
    '이번 주 일정 알려줘',
    '내일 경기',
    '이번 주말 매치 일정',
    '다음 주 시합',
    '8시 경기',
    '주말 동안 매치',
  ],
  my_profile: [
    '내 등급 알려줘',
    '내가 등록한 협회',
    '내 프로필 보여줘',
    '내 점수가 뭐야',
    '내가 가입한 클럽',
    '내 종목 등록 정보',
    '내 즐겨찾기 대회',
  ],
  free_chat: [
    '안녕',
    '추천해줘',
    '도와줘',
    '오늘 어때',
    '뭐가 좋아?',
    '고마워',
    '재밌는 거 있어?',
  ],
};

interface SeedRow {
  intent: Intent;
  example_text: string;
  embedding: string; // pgvector literal
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  // 의도 카테고리/예시 flatten (intent 순서를 응답에서 안정적으로 반환하기 위해 entries 순회).
  const entries = Object.entries(SEED_EXAMPLES) as Array<[Intent, string[]]>;
  const flat: Array<{ intent: Intent; example_text: string }> = [];
  for (const [intent, examples] of entries) {
    for (const text of examples) {
      flat.push({ intent, example_text: text });
    }
  }

  // RETRIEVAL_QUERY task 로 임베딩 — chat/index.ts 가 같은 task type 으로 쿼리하므로 일관 유지.
  // intent_examples 는 "참조 쿼리 예시" 역할이므로 DOCUMENT 가 아니라 QUERY 가 맞다.
  let embeddings: number[][];
  try {
    embeddings = await embedBatch(flat.map((f) => f.example_text), 'RETRIEVAL_QUERY');
  } catch (e) {
    return errorResponse(`embedBatch failed: ${(e as Error).message}`, 502);
  }

  if (embeddings.length !== flat.length) {
    return errorResponse(
      `embedding count mismatch: expected ${flat.length}, got ${embeddings.length}`,
      502,
    );
  }

  const rows: SeedRow[] = flat.map((f, i) => ({
    intent: f.intent,
    example_text: f.example_text,
    embedding: toVectorLiteral(embeddings[i]),
  }));

  const supabase = serviceClient();

  // 멱등성: 기존 행 전체 삭제 후 재삽입. service_role 만 INSERT/DELETE 가능 (RLS).
  // truncate 는 service_role 도 별도 권한 필요 → delete 사용.
  // 시드 규모 (~수십 건) 라 비용 무시 가능.
  const { error: delErr } = await supabase
    .from('intent_examples')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000'); // delete all (Supabase 는 filterless delete 거부)
  if (delErr) {
    return errorResponse(`delete existing failed: ${delErr.message}`, 500);
  }

  const { error: insErr } = await supabase.from('intent_examples').insert(rows);
  if (insErr) {
    return errorResponse(`insert failed: ${insErr.message}`, 500);
  }

  // intent 별 카운트
  const intentCounts: Record<string, number> = {};
  for (const r of rows) {
    intentCounts[r.intent] = (intentCounts[r.intent] ?? 0) + 1;
  }

  return new Response(
    JSON.stringify({
      inserted: rows.length,
      intents: intentCounts,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
});
