// _shared/crawler/types.ts
// Phase 2 dispatcher 와 parser 가 공유하는 인터페이스.
//
// 핵심 규약:
//   - parser 는 audit 를 직접 호출하지 않는다. dispatcher 가 startAudit/finishAudit 일괄 관리.
//   - parser 는 fetch + parse + upsertTournament 만 수행하고, 결과를 CrawlResult 로 반환.
//   - dispatcher 는 그 결과로 crawl_sources 메트릭 컬럼을 갱신.

import type { AuditHandle } from '../crawler.ts';

/**
 * dispatcher 가 parser 에 전달하는 source 정보.
 * crawl_sources 테이블의 일부 컬럼 subset.
 */
export interface CrawlSource {
  slug: string;
  url: string;
  region: string | null;
}

/**
 * parser 호출 컨텍스트 (Phase 4 변경 감지용 ETag/Last-Modified placeholder).
 * 현재는 미사용이지만, 시그니처에 미리 노출해 Phase 4 에서 무파괴 확장 가능하게 한다.
 */
export interface ParserContext {
  audit: AuditHandle;
  previousEtag?: string | null;
  previousLastModified?: string | null;
}

/**
 * parser 가 반환하는 실행 결과.
 *   - status:
 *       'ok'        — 정상 종료 (fetched_count > 0 또는 신규 없음 OK)
 *       'no_change' — ETag/Last-Modified 가 일치해 fetch 생략 (Phase 4)
 *       'error'     — fetchListing 자체가 실패한 경우 (dispatcher 가 finishAudit failed 처리)
 *   - error: status='error' 일 때 메시지
 *   - etag/last_modified: Phase 4 변경 감지용
 */
export interface CrawlResult {
  fetched_count: number;
  inserted_count: number;
  updated_count: number;
  status: 'ok' | 'no_change' | 'error';
  error?: string;
  etag?: string | null;
  last_modified?: string | null;
}

export type ParserFn = (
  source: CrawlSource,
  ctx: ParserContext,
) => Promise<CrawlResult>;
