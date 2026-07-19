import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { GEMINI_MODEL, generateStructured } from '../_shared/gemini.ts';
import { capRegulationBody, normalizeRegulationFields } from '../_shared/regulation.ts';
import { isKatoSource, parseKatoRegulation } from '../_shared/crawler/parsers/kato_regulation.ts';
import { extractPlainText, type RegulationResult, verifyAgainstSource } from './logic.ts';

const BATCH_SIZE = 4;
const LEASE_MINUTES = 15;
const SOURCE_MAX = 12000; // Gemini 입력 상한
const SOURCE_VERIFY_MAX = 50000; // 결정적 파서 값의 원문 대조 상한
const BODY_MAX = 2500; // regulation_body 저장 상한(077 계약)

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    regulation_fields: {
      type: 'array',
      items: {
        type: 'object',
        properties: { label: { type: 'string' }, value: { type: 'string' } },
        required: ['label', 'value'],
      },
    },
    regulation_notes: { type: 'array', items: { type: 'string' } },
    regulation_body: { type: 'string' },
    prize: { type: 'string' },
    format: { type: 'string' },
    description: { type: 'string' },
    confidence: { type: 'number' },
    unusual: { type: 'boolean' },
  },
  required: ['regulation_fields', 'regulation_notes', 'description', 'confidence', 'unusual'],
};

function buildPrompt(title: string, sourceText: string): string {
  return [
    '다음은 동호인 테니스/풋살 대회 공고 원문이다. 요강을 구조화하라.',
    '규칙: 원문에 없는 정보(금액·계좌·날짜 등)를 절대 만들지 말 것. 불명확하면 생략.',
    '값을 지어냈거나 형식이 처음 보는 구조면 unusual=true. 확신도는 confidence(0~1).',
    'regulation_fields는 {label,value} 배열(참가비/입금계좌/시상/일정/접수/경기방식 등),',
    'regulation_notes는 ※ 유의사항 문장 배열, regulation_body는 나머지 서술 본문,',
    'prize는 시상 요약, format은 경기방식 요약, description은 1~2줄 요약.',
    `대회명: ${title}`,
    '원문:',
    sourceText,
  ].join('\n');
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;
  const supabase = serviceClient();
  const result = { processed: 0, needs_review: 0, failed: 0, errors: [] as string[] };

  const { data: claims, error: claimErr } = await supabase
    .rpc('format_pending_claim', { p_batch_size: BATCH_SIZE, p_lease_minutes: LEASE_MINUTES });
  if (claimErr) return errorResponse(`claim failed: ${claimErr.message}`, 500, result);
  const rows = (claims ?? []) as Array<{
    tournament_id: string;
    title: string;
    sport: string;
    source: string;
    claim_token: string;
    document_id: string;
    content_hash: string;
    status: string;
    formatted_at: string | null;
  }>;

  for (const c of rows) {
    try {
      const { data: doc } = await supabase
        .from('crawl_documents').select('raw_html').eq('id', c.document_id).maybeSingle();
      if (!doc?.raw_html) {
        await supabase.rpc('format_pending_fail', {
          p_tid: c.tournament_id,
          p_token: c.claim_token,
        });
        result.failed++;
        continue;
      }
      const rawHtml = doc.raw_html as string;
      const sourceText = extractPlainText(rawHtml, SOURCE_MAX);
      const katoRegulation = isKatoSource(c.source) ? parseKatoRegulation(rawHtml) : null;
      const verificationText = katoRegulation
        ? extractPlainText(rawHtml, SOURCE_VERIFY_MAX)
        : sourceText;

      // KATO의 날짜·장소·계좌·금액은 AI 요약 전에 원본 표에서 전부 확인한다.
      // 핵심 섹션이 하나라도 빠지면 불완전한 내용을 스테이징하지 않고 검수로 보낸다.
      if (isKatoSource(c.source)) {
        const coverageFlags = katoRegulation
          ? katoRegulation.coverage.missingSections.map((section) => ({
            code: 'kato_missing_section',
            field: section,
            masked: '',
          }))
          : [{ code: 'kato_parse_failed', field: '_all', masked: '' }];
        if (
          katoRegulation &&
          katoRegulation.coverage.expectedDivisionCount !==
            katoRegulation.coverage.parsedDivisionCount
        ) {
          coverageFlags.push({
            code: 'kato_division_coverage',
            field: '부서별 장소',
            masked:
              `${katoRegulation.coverage.parsedDivisionCount}/${katoRegulation.coverage.expectedDivisionCount}`,
          });
        }
        if (!katoRegulation || coverageFlags.length > 0) {
          await supabase.rpc('format_pending_reject', {
            p_tid: c.tournament_id,
            p_token: c.claim_token,
            p_flags: coverageFlags,
            p_source_hash: c.content_hash,
          });
          result.needs_review++;
          continue;
        }
      }

      const parsed = await generateStructured<RegulationResult>(
        buildPrompt(c.title, sourceText),
        RESPONSE_SCHEMA,
      );
      const effective: RegulationResult = katoRegulation
        ? {
          ...parsed,
          regulation_fields: katoRegulation.fields,
          regulation_notes: katoRegulation.notes,
          prize: katoRegulation.prize ?? parsed.prize,
        }
        : parsed;
      const fields = normalizeRegulationFields(effective.regulation_fields);
      const verdict = verifyAgainstSource(effective, verificationText);

      if (fields.length === 0 || !verdict.ok) {
        await supabase.rpc('format_pending_reject', {
          p_tid: c.tournament_id,
          p_token: c.claim_token,
          p_flags: fields.length === 0
            ? [{ code: 'empty_fields', field: '_all', masked: '' }, ...verdict.flags]
            : verdict.flags,
          p_source_hash: c.content_hash,
        });
        result.needs_review++;
        continue;
      }

      // 스테이징 판정: 이미 노출 중(published/closed)인데 최초 정형화면 검수 스테이징.
      const stage = (c.status === 'published' || c.status === 'closed') && c.formatted_at === null;
      const { error: compErr } = await supabase.rpc('format_pending_complete', {
        p_tid: c.tournament_id,
        p_token: c.claim_token,
        p_document_id: c.document_id,
        p_source_hash: c.content_hash,
        p_regulation_fields: fields,
        p_regulation_notes: effective.regulation_notes ?? [],
        p_regulation_body: capRegulationBody(effective.regulation_body, BODY_MAX) || null,
        p_prize: effective.prize || null,
        p_format: effective.format || null,
        p_description: effective.description || null,
        p_model: GEMINI_MODEL,
        p_flags: verdict.flags.length ? verdict.flags : null,
        p_stage: stage,
      });
      if (compErr) {
        result.errors.push(`complete ${c.tournament_id}: ${compErr.message}`);
        await supabase.rpc('format_pending_fail', {
          p_tid: c.tournament_id,
          p_token: c.claim_token,
        });
        result.failed++;
      } else if (stage) result.needs_review++;
      else result.processed++;
    } catch (e) {
      result.errors.push(`${c.tournament_id}: ${(e as Error).message}`);
      await supabase.rpc('format_pending_fail', { p_tid: c.tournament_id, p_token: c.claim_token });
      result.failed++;
    }
  }
  return jsonResponse(result);
});
