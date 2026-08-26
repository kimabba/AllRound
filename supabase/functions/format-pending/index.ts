import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';
import {
  GEMINI_MODEL,
  generateStructured,
  generateStructuredWithImage,
} from '../_shared/gemini.ts';
import { capRegulationBody, normalizeRegulationFields } from '../_shared/regulation.ts';
import {
  mergeRegulationDocuments,
  normalizeRegulationDocument,
  REGULATION_DOCUMENT_VERSION,
  regulationDocumentFromLegacy,
  regulationDocumentToBody,
  regulationDocumentToFields,
  regulationDocumentToNotes,
  regulationDocumentVerificationFields,
} from '../_shared/regulation_document.ts';
import { isKatoSource, parseKatoRegulation } from '../_shared/crawler/parsers/kato_regulation.ts';
import {
  extractPlainText,
  type FormatFlag,
  type RegulationResult,
  RESPONSE_SCHEMA,
  verifyAgainstSource,
} from './logic.ts';
import {
  appendPosterSection,
  extractPosterFields,
  fetchPosterImage,
  POSTER_RESPONSE_SCHEMA,
  type PosterExtraction,
  posterFlags,
  type PosterStageDeps,
  posterTargetsMissing,
} from './poster.ts';

const BATCH_SIZE = 4;
const LEASE_MINUTES = 15;
const SOURCE_MAX = 12000; // Gemini 입력 상한
const SOURCE_VERIFY_MAX = 50000; // 결정적 파서 값의 원문 대조 상한
const BODY_MAX = 2500; // regulation_body 저장 상한(077 계약)

interface StructuredRegulationResponse {
  regulation_document: unknown;
  prize: string;
  format: string;
  description: string;
  confidence: number;
  unusual: boolean;
}

function buildPrompt(title: string, sourceText: string): string {
  return [
    '다음은 동호인 테니스/풋살 대회 공고 원문이다. 요강을 고정 문서 구조로 정리하라.',
    '규칙: 원문에 없는 정보(금액·계좌·날짜 등)를 절대 만들지 말 것. 불명확하면 생략.',
    '값을 지어냈거나 형식이 처음 보는 구조면 unusual=true. 확신도는 confidence(0~1).',
    'regulation_document.schema_version은 반드시 1이다.',
    '섹션 code와 순서는 eligibility, schedule_venue, registration_payment, match_operations,',
    'awards, refund_changes, notices_contact, other만 사용한다. 같은 code를 중복 생성하지 않는다.',
    '원문에 내용이 있으면 availability=present, 추후 공지는 not_announced, 해당 없음은 not_applicable.',
    'blocks는 paragraph/subheading/bullets/key_values/table/notice/division_schedule만 사용한다.',
    '대제목은 만들지 말고 section code로만 구분한다. 원문 소제목은 subheading에 넣는다.',
    '입금계좌가 원문에 있으면 key_values 또는 division_schedule에 은행명·계좌번호·예금주를 포함한다.',
    '부서마다 일정·장소·참가비·계좌가 다르면 division_schedule 배열에서 부서별로 분리한다.',
    '표는 columns와 rows[{cells}]로 보존하고, 일반 설명은 paragraph, 열거는 bullets로 정리한다.',
    'prize/시상은 순위·부서별 상금액을 원문 그대로 구체적으로(예: 우승 30만원, 준우승 15만원). 뭉뚱그리지 말 것.',
    'format은 경기방식 요약, description은 1~2줄 요약.',
    `대회명: ${title}`,
    '원문:',
    sourceText,
  ].join('\n');
}

Deno.serve(withCors(async (req) => {
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

  // 포스터 보완 단계(P6) 판정용 부가 정보. claim RPC 반환에 없어서 따로 읽는다.
  interface PosterExtra {
    id: string;
    poster_url: string | null;
    entry_fee: number | null;
    location: string | null;
    poster_vision_at: string | null;
  }
  const posterExtras = new Map<string, PosterExtra>();
  if (rows.length > 0) {
    const { data: extraRows, error: extraErr } = await supabase
      .from('tournaments')
      .select('id, poster_url, entry_fee, location, poster_vision_at')
      .in('id', rows.map((r) => r.tournament_id));
    // 실패해도 배치 자체는 계속한다(포스터 단계만 건너뜀) — 관측용 로그만 남긴다.
    if (extraErr) console.error('poster extras select failed:', extraErr.message);
    for (const row of (extraRows ?? []) as PosterExtra[]) posterExtras.set(row.id, row);
  }
  const posterDeps: PosterStageDeps = {
    fetchImage: (url) => fetchPosterImage(url),
    generate: (prompt, image) =>
      generateStructuredWithImage<PosterExtraction>(prompt, image, POSTER_RESPONSE_SCHEMA, {
        maxOutputTokens: 1024,
      }),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  };

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

      const parsed = await generateStructured<StructuredRegulationResponse>(
        buildPrompt(c.title, sourceText),
        RESPONSE_SCHEMA,
        { maxOutputTokens: 6144 },
      );
      const aiDocument = normalizeRegulationDocument(parsed.regulation_document);
      if (!aiDocument) {
        await supabase.rpc('format_pending_reject', {
          p_tid: c.tournament_id,
          p_token: c.claim_token,
          p_flags: [{ code: 'invalid_document', field: '_all', masked: '' }],
          p_source_hash: c.content_hash,
        });
        result.needs_review++;
        continue;
      }
      const deterministicDocument = katoRegulation
        ? regulationDocumentFromLegacy(katoRegulation.fields, katoRegulation.notes)
        : null;
      let document = mergeRegulationDocuments(deterministicDocument, aiDocument);
      let fields = normalizeRegulationFields(regulationDocumentToFields(document));
      const effective: RegulationResult = {
        regulation_fields: regulationDocumentVerificationFields(document),
        regulation_notes: regulationDocumentToNotes(document),
        regulation_body: regulationDocumentToBody(document),
        prize: katoRegulation?.prize ?? parsed.prize,
        format: parsed.format,
        description: parsed.description,
        confidence: parsed.confidence,
        unusual: parsed.unusual,
      };
      const verdict = verifyAgainstSource(effective, verificationText);

      if (!verdict.ok) {
        await supabase.rpc('format_pending_reject', {
          p_tid: c.tournament_id,
          p_token: c.claim_token,
          p_flags: verdict.flags,
          p_source_hash: c.content_hash,
        });
        result.needs_review++;
        continue;
      }

      // ── 포스터 보완 단계 (P6) ──
      // 원문 텍스트에서 참가비/장소가 확보되지 않았고 포스터가 있으면 이미지에서
      // 보충 추출한다. 원문 대조(verifyAgainstSource)를 통과한 문서에만 덧붙인다 —
      // 포스터 항목은 대조가 불가능하므로 verdict 이후에 붙이고, 아래에서 스테이징을
      // 강제해 검수함(needs_review) 경유로만 반영한다.
      let posterFlagList: FormatFlag[] = [];
      const extra = posterExtras.get(c.tournament_id);
      if (
        extra?.poster_url && !extra.poster_vision_at &&
        posterTargetsMissing(fields, extra.entry_fee, extra.location)
      ) {
        const poster = await extractPosterFields(posterDeps, c.title, extra.poster_url);
        // 대회당 1회 호출 보장: 성공/실패와 무관하게 시도를 기록해 재큐 시 재호출을 막는다.
        const { error: markErr } = await supabase
          .from('tournaments')
          .update({ poster_vision_at: new Date().toISOString() })
          .eq('id', c.tournament_id);
        if (markErr) result.errors.push(`poster mark ${c.tournament_id}: ${markErr.message}`);
        if (poster.ok && poster.entries.length > 0) {
          document = appendPosterSection(document, poster.entries);
          fields = normalizeRegulationFields(regulationDocumentToFields(document));
          effective.regulation_notes = regulationDocumentToNotes(document);
          effective.regulation_body = regulationDocumentToBody(document);
          posterFlagList = posterFlags(poster.entries);
        } else if (!poster.ok) {
          result.errors.push(`poster ${c.tournament_id}: ${poster.reason}`);
        }
      }

      // 스테이징 판정: 이미 노출 중(published/closed)인데 최초 정형화면 검수 스테이징.
      // 포스터 추출이 섞였으면 원문 대조가 불가능하므로 **무조건** 스테이징한다.
      const stage = ((c.status === 'published' || c.status === 'closed') &&
        c.formatted_at === null) || posterFlagList.length > 0;
      const allFlags = [...verdict.flags, ...posterFlagList];
      const { error: compErr } = await supabase.rpc('format_pending_complete_v2', {
        p_tid: c.tournament_id,
        p_token: c.claim_token,
        p_document_id: c.document_id,
        p_source_hash: c.content_hash,
        p_regulation_document: document,
        p_regulation_schema_version: REGULATION_DOCUMENT_VERSION,
        p_regulation_fields: fields,
        p_regulation_notes: effective.regulation_notes ?? [],
        p_regulation_body: capRegulationBody(effective.regulation_body, BODY_MAX) || null,
        p_prize: effective.prize || null,
        p_format: effective.format || null,
        p_description: effective.description || null,
        p_model: GEMINI_MODEL,
        p_flags: allFlags.length ? allFlags : null,
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
}));
