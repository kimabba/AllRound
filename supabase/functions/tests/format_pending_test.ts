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

Deno.test('verifyAgainstSource: 문의처(전화번호)는 원문에 없어도 flag 안 함 (공유 문의 섹션 크롤 누락 오탐 방지)', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '문의처', value: '010-9999-8888' }],
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

Deno.test('verifyAgainstSource: 입금계좌는 여전히 원문 대조 검증됨 (문의처 예외의 회귀 방지)', () => {
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
});

Deno.test('verifyAgainstSource: 대회 임원 직책 라벨(사무장/경기이사/총무)의 전화번호는 오탐 제외됨', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  for (const label of ['사무장', '경기이사', '총무']) {
    const r = verifyAgainstSource({
      regulation_fields: [{ label, value: '010-9999-8888' }],
      regulation_notes: [],
      regulation_body: '',
      prize: '',
      format: '',
      description: '',
      confidence: 0.9,
      unusual: false,
    }, src);
    assertEquals(r.ok, true, `${label} 라벨의 전화번호가 오탐 flag됨`);
  }
});

Deno.test('verifyAgainstSource: 임원 직책 라벨이라도 계좌번호(전화 형태 아님)는 여전히 검증됨', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  for (const label of ['사무장', '경기이사', '총무']) {
    const r = verifyAgainstSource({
      regulation_fields: [{ label, value: '국민 999-8888-7777' }],
      regulation_notes: [],
      regulation_body: '',
      prize: '',
      format: '',
      description: '',
      confidence: 0.9,
      unusual: false,
    }, src);
    assertEquals(r.ok, false, `${label} 라벨의 계좌번호가 오탐 제외됨(검증 완화 회귀)`);
  }
});

Deno.test('verifyAgainstSource: 라벨에 "계좌"가 함께 있으면 임원 직책 단어가 섞여도 대조 제외 안 됨', () => {
  // "입금계좌 안내" 처럼 CONTACT_LABEL(안내)과 계좌가 한 라벨에 같이 오는 우발 매칭 방지.
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '입금계좌 안내', value: '국민 999-8888-7777' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
});

Deno.test('verifyAgainstSource: 계좌류 라벨("입금 안내")의 전화 모양 계좌는 여전히 검증됨', () => {
  // 휴대폰 평생계좌처럼 010 번호 자체가 계좌인 실사례 — 라벨의 입금/납부/송금/통장
  // 키워드가 CONTACT_LABEL('안내')보다 우선해야 한다(검증 완화 회귀 방지).
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '입금 안내', value: 'IBK 010-9999-8888' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
  assert(r.flags.some((f) => f.code === 'not_in_source' && f.field === '입금 안내'));
});

Deno.test('verifyAgainstSource: 임원 직책 라벨이라도 값에 계좌류 키워드가 있으면 전화 모양도 검증됨', () => {
  // 실측 사례: label "총무", value "기업은행 계좌 010-…" — 값의 계좌 키워드가 제외를 무효화.
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '총무', value: '기업은행 계좌 010-1234-5678' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
  assert(r.flags.some((f) => f.code === 'not_in_source' && f.field === '총무'));
});

Deno.test('verifyAgainstSource: 값에 "예금주" 병기된 전화 모양 계좌는 임원 라벨이라도 검증됨', () => {
  // 계좌 표기의 표준 관행("… 예금주 홍길동")이 계좌·입금 키워드를 모두 피해가는 변형을 막는다.
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const r = verifyAgainstSource({
    regulation_fields: [{ label: '총무', value: 'IBK 010-1234-5678 예금주 홍길동' }],
    regulation_notes: [],
    regulation_body: '',
    prize: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  }, src);
  assertEquals(r.ok, false);
  assert(r.flags.some((f) => f.code === 'not_in_source' && f.field === '총무'));
});

Deno.test('verifyAgainstSource: prize의 지어낸 상금도 원문 대조 flag (검증 우회 방지)', () => {
  // 참고: '30만원' 같은 한글 단위 금액은 sensitiveTokens가 추출하지 않는 기존 한계
  // (전 필드 공통, HANDOFF §3 보류 항목) — 여기서는 숫자원 표기로 배선 자체를 검증.
  const src = '시상: 우승 300,000원, 준우승 150,000원';
  const base = {
    regulation_fields: [],
    regulation_notes: [],
    regulation_body: '',
    format: '',
    description: '',
    confidence: 0.9,
    unusual: false,
  };
  const good = verifyAgainstSource({ ...base, prize: '우승 300,000원, 준우승 150,000원' }, src);
  assertEquals(good.ok, true);
  const bad = verifyAgainstSource({ ...base, prize: '우승 990,000원' }, src);
  assertEquals(bad.ok, false);
  const flag = bad.flags.find((f) => f.field === '시상');
  assert(flag !== undefined);
});
