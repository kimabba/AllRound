import type { SupabaseClient } from '@supabase/supabase-js';
import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { embedBatch, toVectorLiteral } from '../_shared/embedding.ts';
import { normalizeRegulationFields, regulationEmbeddingText } from '../_shared/regulation.ts';

/**
 * pg_cron 이 5분마다 호출.
 * 임베딩이 없거나 stale 한 tournaments / rule_articles 를 배치 처리.
 *
 * 인증: pg_cron → invoke_edge_function() 가 INTERNAL_CRON_JWT 로 호출.
 *       (Functions 의 verify_jwt 는 supabase/config.toml 에서 false 로 설정)
 */
const BATCH_SIZE = 32;

export interface TournamentSelectSpec {
  columns: string;
  onlyStatus: 'published';
  excludeFormatStatus: ['pending', 'processing'];
}

export function buildTournamentSelect(): TournamentSelectSpec {
  return {
    columns:
      'id, title, description, region, format, organizer, regulation_fields, regulation_body, embedding_input_revision',
    onlyStatus: 'published',
    excludeFormatStatus: ['pending', 'processing'],
  };
}

interface PendingTournament {
  id: string;
  title: string;
  description: string | null;
  region: string | null;
  format: string | null;
  organizer: string | null;
  // 요강(regulation): migration 077 에서 임베딩 입력에 포함하기로 결정.
  // regulation_fields 는 jsonb 라서 unknown 으로 받고 사용 시 narrow.
  regulation_fields: unknown;
  regulation_body: string | null;
  embedding_input_revision: number;
}

interface PendingRule {
  id: string;
  title: string;
  body: string;
}

function tournamentText(t: PendingTournament): string {
  const base = [t.title, t.organizer, t.region, t.format, t.description]
    .filter(Boolean)
    .join(' / ');
  // 요강(요강 fields + 본문)을 임베딩 입력에 포함 → "경기방식/시상/참가자격" 류
  // 질문이 시맨틱 검색에 매칭되도록. 본문은 임베딩 입력 비대화 방지를 위해 cap.
  const regulation = regulationEmbeddingText(
    normalizeRegulationFields(t.regulation_fields),
    t.regulation_body,
  );
  return regulation ? `${base}\n${regulation}` : base;
}

function ruleText(r: PendingRule): string {
  return `${r.title}\n${r.body}`.slice(0, 4000);
}

type EmbedFn = (texts: string[]) => Promise<number[][]>;

export async function runTournamentEmbedding(
  supabase: SupabaseClient,
  embed: EmbedFn,
): Promise<{ processed: number; skipped: number; errors: string[] }> {
  const out = { processed: 0, skipped: 0, errors: [] as string[] };
  const sel = buildTournamentSelect();
  const { data: pending } = await supabase
    .from('tournaments')
    .select(sel.columns)
    .is('embedding', null)
    .eq('status', sel.onlyStatus)
    .not('format_status', 'in', '("pending","processing")')
    .limit(BATCH_SIZE);
  if (!pending || pending.length === 0) return out;

  const rows = pending as unknown as PendingTournament[];
  const texts = rows.map((t) => tournamentText(t));
  const embeddings = await embed(texts);
  const now = new Date().toISOString();
  for (let i = 0; i < rows.length; i++) {
    const { data, error } = await supabase
      .from('tournaments')
      .update({ embedding: toVectorLiteral(embeddings[i]), embedding_updated_at: now })
      .eq('id', rows[i].id)
      .eq('embedding_input_revision', rows[i].embedding_input_revision) // optimistic: 그새 바뀌면 0행
      .select('id');
    if (error) out.errors.push(`tournament ${rows[i].id}: ${error.message}`);
    else if (!data || data.length === 0) out.skipped++; // revision 변경 → 다음 사이클 재생성
    else out.processed++;
  }
  return out;
}

async function handler(req: Request): Promise<Response> {
  const pre = preflight(req);
  if (pre) return pre;

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const supabase = serviceClient();

  const result = {
    tournaments_processed: 0,
    rules_processed: 0,
    errors: [] as string[],
  };

  // ---- tournaments ----
  try {
    const r = await runTournamentEmbedding(supabase, embedBatch);
    result.tournaments_processed += r.processed;
    result.errors.push(...r.errors);
  } catch (e) {
    result.errors.push(`tournaments batch: ${(e as Error).message}`);
  }

  // ---- rule_articles ----
  try {
    const { data: pending } = await supabase
      .from('rule_articles')
      .select('id, title, body')
      .is('embedding', null)
      .eq('published', true)
      .limit(BATCH_SIZE);

    if (pending && pending.length > 0) {
      const texts = pending.map((r) => ruleText(r as PendingRule));
      const embeddings = await embedBatch(texts);
      const now = new Date().toISOString();
      for (let i = 0; i < pending.length; i++) {
        const { error } = await supabase
          .from('rule_articles')
          .update({
            embedding: toVectorLiteral(embeddings[i]),
            embedding_updated_at: now,
          })
          .eq('id', pending[i].id);
        if (error) result.errors.push(`rule ${pending[i].id}: ${error.message}`);
        else result.rules_processed++;
      }
    }
  } catch (e) {
    result.errors.push(`rules batch: ${(e as Error).message}`);
  }

  if (result.errors.length > 0 && result.tournaments_processed + result.rules_processed === 0) {
    return errorResponse('All embeddings failed', 500, result);
  }
  return jsonResponse(result);
}

if (import.meta.main) {
  Deno.serve(handler);
}
