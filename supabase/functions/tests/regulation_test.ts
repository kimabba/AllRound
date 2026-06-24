import { assertEquals } from 'std/assert/mod.ts';
import {
  buildRegulationContextLines,
  capRegulationBody,
  formatRegulationFields,
  normalizeRegulationFields,
  regulationEmbeddingText,
  type RegulationField,
} from '../_shared/regulation.ts';

Deno.test('normalizeRegulationFields keeps valid label/value pairs in order', () => {
  const raw = [
    { label: '장소', value: '진월국제테니스장' },
    { label: '주최', value: '광주광역시테니스협회' },
  ];
  assertEquals(normalizeRegulationFields(raw), raw);
});

Deno.test('normalizeRegulationFields trims and drops invalid entries', () => {
  const raw = [
    { label: '  장소  ', value: '  코트A ' },
    { label: '시상', value: '' }, // 빈 value → 제외
    { label: '', value: '값' }, // 빈 label → 제외
    { label: '주최', value: 42 }, // 비문자 value → 제외
    null, // 비객체 → 제외
    'string', // 비객체 → 제외
  ];
  assertEquals(normalizeRegulationFields(raw), [{ label: '장소', value: '코트A' }]);
});

Deno.test('normalizeRegulationFields returns [] for non-array input', () => {
  assertEquals(normalizeRegulationFields(null), []);
  assertEquals(normalizeRegulationFields(undefined), []);
  assertEquals(normalizeRegulationFields({ label: 'x', value: 'y' }), []);
  assertEquals(normalizeRegulationFields('nope'), []);
});

Deno.test('formatRegulationFields joins label:value with separator', () => {
  const fields: RegulationField[] = [
    { label: '장소', value: '코트A' },
    { label: '시상', value: '1위 상금' },
  ];
  assertEquals(formatRegulationFields(fields), '장소: 코트A / 시상: 1위 상금');
  assertEquals(formatRegulationFields([]), '');
});

Deno.test('capRegulationBody truncates over maxLen with ellipsis', () => {
  assertEquals(capRegulationBody('abcdef', 3), 'abc…');
  assertEquals(capRegulationBody('abc', 3), 'abc');
  assertEquals(capRegulationBody('  spaced  ', 10), 'spaced');
  assertEquals(capRegulationBody(null, 10), '');
  assertEquals(capRegulationBody('   ', 10), '');
});

Deno.test('regulationEmbeddingText combines fields summary and capped body', () => {
  const fields: RegulationField[] = [{ label: '경기방식', value: '단식 토너먼트' }];
  const text = regulationEmbeddingText(fields, '본문입니다', 1500);
  assertEquals(text, '경기방식: 단식 토너먼트\n본문입니다');
});

Deno.test('regulationEmbeddingText empty when nothing present', () => {
  assertEquals(regulationEmbeddingText([], null), '');
  assertEquals(regulationEmbeddingText([], '   '), '');
});

Deno.test('regulationEmbeddingText caps long body', () => {
  const longBody = 'x'.repeat(2000);
  const text = regulationEmbeddingText([], longBody, 50);
  // 50자 + … = 51 길이
  assertEquals(text.length, 51);
  assertEquals(text.endsWith('…'), true);
});

Deno.test('buildRegulationContextLines emits 요강 + 요강 본문 lines', () => {
  const fields: RegulationField[] = [
    { label: '장소', value: '코트A' },
    { label: '시상', value: '메달' },
  ];
  const lines = buildRegulationContextLines(fields, '경기는 단식으로 진행합니다.', {
    bodyCap: 1200,
    prefix: '  ',
  });
  assertEquals(lines, [
    '  요강: 장소: 코트A / 시상: 메달',
    '  요강 본문: 경기는 단식으로 진행합니다.',
  ]);
});

Deno.test('buildRegulationContextLines flattens newlines in body', () => {
  const lines = buildRegulationContextLines([], '첫째 줄\n둘째 줄', { prefix: '' });
  assertEquals(lines, ['요강 본문: 첫째 줄 둘째 줄']);
});

Deno.test('buildRegulationContextLines returns [] when no data', () => {
  assertEquals(buildRegulationContextLines([], null), []);
  assertEquals(buildRegulationContextLines([], '  '), []);
});

Deno.test('buildRegulationContextLines includes fields only when body absent', () => {
  const fields: RegulationField[] = [{ label: '참가자격', value: '동호인 누구나' }];
  const lines = buildRegulationContextLines(fields, null, { prefix: '' });
  assertEquals(lines, ['요강: 참가자격: 동호인 누구나']);
});
