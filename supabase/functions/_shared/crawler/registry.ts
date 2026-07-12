// _shared/crawler/registry.ts
// crawl_sources.parser_module 값 → parser 함수 매핑.
//
// 새 사이트 추가 흐름:
//   1) parsers/ 에 새 *.ts 작성 (export const fooParser: ParserFn = ...)
//   2) 이 파일에 import + PARSER_REGISTRY 에 등록
//   3) 어드민 UI 에서 crawl_sources row 추가 (parser_module = 키 문자열)
//
// dispatcher 가 PARSER_REGISTRY[source.parser_module] 로 lookup;
// 매핑이 없으면 그 source 는 error 로 기록되고 skip.
//
// History:
//   2026-05-21 — 사이트 리뉴얼 대응. 광주/전남이 sub5_5.php (대회공지사항) 으로
//   이동하고 두 사이트 HTML 구조가 동일해져 통합 parser 'gnuboard-sub5-5-contest'
//   하나로 처리. 옛 'tennis-gwangju-board' / 'tennis-jeonnam-board' / 'tennis-korea-board'
//   parser 와 thin wrapper edge functions 제거 (migration 024 참고).

import { gnuboardSub5_5ContestParser } from './parsers/gnuboard_sub5_5_contest.ts';
import { katoOpenListParser } from './parsers/kato_openlist.ts';
import type { ParserFn } from './types.ts';

export const PARSER_REGISTRY: Record<string, ParserFn> = {
  'gnuboard-sub5-5-contest': gnuboardSub5_5ContestParser,
  'kato-openlist': katoOpenListParser,
};

export function getParser(key: string): ParserFn | undefined {
  return PARSER_REGISTRY[key];
}

export function listParserKeys(): string[] {
  return Object.keys(PARSER_REGISTRY);
}
