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

Deno.test('verifyAgainstSource: 무관한 숫자들의 전체 concat과 우연히 일치하는 조작값도 flag (개별 런 매칭)', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '입금계좌', value: '국민 0030-2123-4567' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
  const flag = r.flags.find((f) => f.field === '입금계좌');
  assert(flag !== undefined);
  assert(!flag!.masked.includes('2123'));
});

Deno.test('verifyAgainstSource: 계좌/날짜 정규식이 겹쳐도 동일 필드에 중복 flag 없음', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '접수마감', value: '2099-12-31' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  const dupFlags = r.flags.filter((f) => f.code === 'not_in_source' && f.field === '접수마감');
  assertEquals(dupFlags.length, 1);
});

Deno.test('verifyAgainstSource: 공백으로만 붙은 서로 다른 두 계좌 사이 경계를 넘나드는 조작값은 flag', () => {
  const src = '계좌 302-1234-5678 999-8888-7777 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '입금계좌', value: '하나 5678-9998-8887' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
  const flag = r.flags.find((f) => f.field === '입금계좌');
  assert(flag !== undefined);
});

Deno.test('verifyAgainstSource: 공백으로만 붙은 두 실제 계좌는 각각 개별 검증 통과', () => {
  const src = '계좌 302-1234-5678 999-8888-7777 입금';
  const r = verifyAgainstSource({
    regulation_fields: [
      { label: '계좌1', value: '302-1234-5678' },
      { label: '계좌2', value: '999-8888-7777' },
    ],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, true);
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
