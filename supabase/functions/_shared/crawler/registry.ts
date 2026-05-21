// _shared/crawler/registry.ts
// crawl_sources.parser_module 값 → parser 함수 매핑.
//
// 새 사이트 추가 흐름:
//   1) parsers/ 에 새 *_board.ts 작성 (export const fooParser: ParserFn = ...)
//   2) 이 파일에 import + PARSER_REGISTRY 에 등록
//   3) 어드민 UI 에서 crawl_sources row 추가 (parser_module = 키 문자열)
//
// dispatcher 가 PARSER_REGISTRY[source.parser_module] 로 lookup;
// 매핑이 없으면 그 source 는 error 로 기록되고 skip.

import { tennisGwangjuBoardParser } from './parsers/tennis_gwangju_board.ts';
import { tennisJeonnamBoardParser } from './parsers/tennis_jeonnam_board.ts';
import { tennisKoreaBoardParser } from './parsers/tennis_korea_board.ts';
import type { ParserFn } from './types.ts';

export const PARSER_REGISTRY: Record<string, ParserFn> = {
  'tennis-gwangju-board': tennisGwangjuBoardParser,
  'tennis-jeonnam-board': tennisJeonnamBoardParser,
  'tennis-korea-board': tennisKoreaBoardParser,
};

export function getParser(key: string): ParserFn | undefined {
  return PARSER_REGISTRY[key];
}

export function listParserKeys(): string[] {
  return Object.keys(PARSER_REGISTRY);
}
