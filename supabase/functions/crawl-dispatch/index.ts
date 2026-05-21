// supabase/functions/crawl-dispatch/index.ts
// Phase 2: 단일 진입점 크롤 dispatcher.
//
// 호출 경로:
//   - pg_cron 'crawl-dispatch' (*/15 * * * *) — body 없음 / GET → 전체 enabled sources 평가
//   - 어드민 UI "수동 실행" → POST { slug, force: true } → 1건 즉시 실행
//   - 외부 / thin wrapper Edge Function → POST { slug } → schedule 평가
//
// 권한: requireServiceRoleOrAdmin (service_role JWT 또는 admin user JWT)
//
// 흐름:
//   1) crawl_sources SELECT (enabled = true, slug 일치 또는 전체)
//   2) source 별 schedule 평가:
//        - body.force === true 또는 body.slug 명시 → 무조건 실행
//        - 아니면 last_crawled_at 이 null 이거나 20시간 이상 지났으면 실행
//        - (정밀 cron parser 는 의도적으로 도입 안 함 — MVP 는 "하루 1회" 보장)
//   3) PARSER_REGISTRY 에서 parser_module 매핑 lookup
//        - 매핑 없음 → executed 에 status='error' 로 기록 + crawl_sources.last_error 갱신
//   4) startAudit(slug) → parser(source, ctx) → finishAudit(상태)
//   5) crawl_sources UPDATE (last_crawled_at, last_status, last_error, last_fetched_count,
//      last_etag, last_modified)
//   6) JSON 응답 { executed: [...], skipped: [...], errors: [...] }

import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { finishAudit, startAudit } from '../_shared/crawler.ts';
import { getParser } from '../_shared/crawler/registry.ts';
import type { CrawlResult, CrawlSource } from '../_shared/crawler/types.ts';
import { serviceClient } from '../_shared/supabase.ts';

interface DispatchRequest {
  slug?: string;
  force?: boolean;
}

interface SourceRow {
  id: string;
  slug: string;
  url: string;
  region: string | null;
  parser_module: string;
  enabled: boolean;
  last_crawled_at: string | null;
  last_etag: string | null;
  last_modified: string | null;
}

interface ExecutedEntry {
  slug: string;
  parser_module: string;
  status: CrawlResult['status'];
  fetched_count: number;
  inserted_count: number;
  updated_count: number;
  error?: string;
}

interface SkippedEntry {
  slug: string;
  reason:
    | 'not_due'
    | 'disabled'
    | 'unknown_parser'
    | 'already_running_or_stale';
  last_crawled_at?: string | null;
}

// 최소 실행 간격(시간). schedule_cron 표현식의 정밀 평가 대신 사용.
// MVP: 하루 1회 보장. body.force 또는 body.slug 명시 시 무시.
const MIN_INTERVAL_HOURS = 20;

function isDue(lastCrawledAt: string | null): boolean {
  if (!lastCrawledAt) return true;
  const last = Date.parse(lastCrawledAt);
  if (Number.isNaN(last)) return true;
  const ageHours = (Date.now() - last) / (1000 * 60 * 60);
  return ageHours >= MIN_INTERVAL_HOURS;
}

async function parseRequestBody(req: Request): Promise<DispatchRequest> {
  if (req.method === 'GET') return {};
  try {
    const text = await req.text();
    if (!text) return {};
    const parsed = JSON.parse(text) as unknown;
    if (parsed && typeof parsed === 'object') {
      const obj = parsed as Record<string, unknown>;
      const slug = typeof obj.slug === 'string' ? obj.slug : undefined;
      const force = obj.force === true;
      return { slug, force };
    }
    return {};
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;

  const body = await parseRequestBody(req);
  const supabase = serviceClient();

  // 1) sources 로드
  let query = supabase
    .from('crawl_sources')
    .select(
      'id, slug, url, region, parser_module, enabled, last_crawled_at, last_etag, last_modified',
    )
    .eq('enabled', true);
  if (body.slug) query = query.eq('slug', body.slug);

  const { data: rows, error: loadErr } = await query;
  if (loadErr) {
    return errorResponse(`load sources failed: ${loadErr.message}`, 500);
  }
  const sources = (rows ?? []) as SourceRow[];

  // slug 명시했는데 enabled row 없음 → 명확한 404
  if (body.slug && sources.length === 0) {
    return errorResponse(`source not found or disabled: ${body.slug}`, 404);
  }

  const executed: ExecutedEntry[] = [];
  const skipped: SkippedEntry[] = [];
  const errors: string[] = [];

  // body.slug 명시 또는 force 면 schedule 무시
  const skipSchedule = body.force === true || typeof body.slug === 'string';

  for (const row of sources) {
    if (!skipSchedule && !isDue(row.last_crawled_at)) {
      skipped.push({
        slug: row.slug,
        reason: 'not_due',
        last_crawled_at: row.last_crawled_at,
      });
      continue;
    }

    const parser = getParser(row.parser_module);
    if (!parser) {
      const msg = `unknown parser_module: ${row.parser_module}`;
      errors.push(`${row.slug}: ${msg}`);
      skipped.push({ slug: row.slug, reason: 'unknown_parser' });
      // crawl_sources 메트릭에도 기록 (운영자가 어드민 UI 에서 즉시 확인 가능)
      await supabase
        .from('crawl_sources')
        .update({
          last_crawled_at: new Date().toISOString(),
          last_status: 'error',
          last_error: msg,
          last_fetched_count: 0,
        })
        .eq('id', row.id);
      continue;
    }

    const sourceArg: CrawlSource = {
      slug: row.slug,
      url: row.url,
      region: row.region,
    };

    // B6 (Codex 검토): 동시 실행 방지 — DB 컬럼 advisory lock 패턴.
    // crawl_try_start: NULL 또는 stale (15분 초과) 일 때만 set + true,
    //                  점유 중이면 NULL 반환.
    // RPC 자체가 단일 UPDATE ... RETURNING 이라 race condition 안전.
    const { data: started, error: lockErr } = await supabase.rpc(
      'crawl_try_start',
      { p_slug: row.slug },
    );
    if (lockErr) {
      const msg = `crawl_try_start failed: ${lockErr.message}`;
      errors.push(`${row.slug}: ${msg}`);
      skipped.push({ slug: row.slug, reason: 'already_running_or_stale' });
      continue;
    }
    if (started !== true) {
      // 다른 호출 (cron 또는 수동) 이 이미 점유 중 → 중복 실행 방지로 skip.
      skipped.push({ slug: row.slug, reason: 'already_running_or_stale' });
      continue;
    }

    try {
      const audit = await startAudit(row.slug);
      let result: CrawlResult;
      try {
        result = await parser(sourceArg, {
          audit,
          previousEtag: row.last_etag,
          previousLastModified: row.last_modified,
        });
      } catch (e) {
        const msg = (e as Error).message;
        await finishAudit(audit, 'failed', msg);
        await supabase
          .from('crawl_sources')
          .update({
            last_crawled_at: new Date().toISOString(),
            last_status: 'error',
            last_error: msg,
            last_fetched_count: audit.fetched,
          })
          .eq('id', row.id);
        executed.push({
          slug: row.slug,
          parser_module: row.parser_module,
          status: 'error',
          fetched_count: audit.fetched,
          inserted_count: audit.inserted,
          updated_count: audit.updated,
          error: msg,
        });
        errors.push(`${row.slug}: ${msg}`);
        continue;
      }

      // audit finish 상태 결정
      //   status='ok' + error 있음 → 'partial' (일부 detail 실패)
      //   status='ok' + error 없음 → 'success'
      //   status='no_change'       → 'success' (fetched=0)
      //   status='error'           → 'failed' (listing 자체 실패)
      let auditStatus: 'success' | 'partial' | 'failed';
      if (result.status === 'error') auditStatus = 'failed';
      else if (result.error && result.error.length > 0) auditStatus = 'partial';
      else auditStatus = 'success';
      await finishAudit(audit, auditStatus, result.error);

      // crawl_sources 메트릭 갱신
      const lastStatus = result.status === 'error'
        ? 'error'
        : result.status === 'no_change'
        ? 'no_change'
        : 'ok';
      await supabase
        .from('crawl_sources')
        .update({
          last_crawled_at: new Date().toISOString(),
          last_status: lastStatus,
          last_error: result.error ?? null,
          last_fetched_count: result.fetched_count,
          // Phase 4 확장: undefined 면 컬럼 유지 (null 로 덮어쓰지 않음)
          ...(result.etag !== undefined ? { last_etag: result.etag } : {}),
          ...(result.last_modified !== undefined ? { last_modified: result.last_modified } : {}),
        })
        .eq('id', row.id);

      executed.push({
        slug: row.slug,
        parser_module: row.parser_module,
        status: result.status,
        fetched_count: result.fetched_count,
        inserted_count: result.inserted_count,
        updated_count: result.updated_count,
        error: result.error,
      });
      if (result.status === 'error') {
        errors.push(`${row.slug}: ${result.error ?? 'unknown error'}`);
      }
    } finally {
      // 성공/실패/예외 모두 lock 해제. 15분 stale timeout 도 있지만
      // 정상 종료 시 즉시 해제하는 게 다음 cron tick 까지 기다리지 않아 좋다.
      const { error: relErr } = await supabase.rpc('crawl_release', {
        p_slug: row.slug,
      });
      if (relErr) {
        errors.push(`${row.slug}: crawl_release failed: ${relErr.message}`);
      }
    }
  }

  return jsonResponse({
    executed,
    skipped,
    errors,
    requested: { slug: body.slug ?? null, force: body.force === true },
  });
});
