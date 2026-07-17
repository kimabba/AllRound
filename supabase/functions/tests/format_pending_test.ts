import { assert, assertEquals } from 'std/assert/mod.ts';
import { extractPlainText, maskValue, verifyAgainstSource } from '../format-pending/logic.ts';

Deno.test('extractPlainText: 태그 제거 + 절단', () => {
  const html = '<div>안녕<script>x=1</script> <b>세계</b></div>';
  assertEquals(extractPlainText(html, 100), '안녕 세계');
  assertEquals(extractPlainText('a'.repeat(50), 10).length, 10);
});

Deno.test('maskValue: 계좌/금액 뒷자리 마스킹', () => {
  assert(maskValue('123-4567-8901').includes('*'));
});

Deno.test('verifyAgainstSource: 원문에 없는 계좌/금액이면 flag', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const good = verifyAgainstSource({
    regulation_fields: [{ label: '참가비', value: '64,000원' }, {
      label: '입금계좌',
      value: '농협 302-1234-5678',
    }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(good.ok, true);
  const bad = verifyAgainstSource({
    regulation_fields: [{ label: '입금계좌', value: '국민 999-8888-7777' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(bad.ok, false);
  assert(bad.flags.length >= 1);
  assert(!bad.flags[0].masked.includes('8888')); // 마스킹됨
});

Deno.test('verifyAgainstSource: unusual=true면 flag', () => {
  const r = verifyAgainstSource({
    regulation_fields: [],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: true,
  }, 'src');
  assertEquals(r.ok, false);
});
