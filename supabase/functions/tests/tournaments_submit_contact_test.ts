import { assertEquals } from 'std/assert/mod.ts';
import { parseSubmitBody, validateSubmissionContact } from '../tournaments-submit/index.ts';

const basePayload = {
  sport: 'tennis',
  title: '담당자 정보 테스트 대회',
  start_date: '2026-09-01',
  eligible_grades: ['gj_m_gold'],
};

Deno.test('대회 제보 담당자 이름과 연락처를 파싱한다', () => {
  const parsed = parseSubmitBody({
    ...basePayload,
    contact_name: ' 홍길동 ',
    contact_value: ' play@example.com ',
  });
  if ('error' in parsed) throw new Error(parsed.error);
  assertEquals(parsed.value.contact_name, ' 홍길동 ');
  assertEquals(parsed.value.contact_value, ' play@example.com ');
});

Deno.test('담당자 이름과 연락처는 함께 입력해야 한다', () => {
  assertEquals(
    validateSubmissionContact('홍길동', undefined),
    { error: 'contact_name and contact_value must be provided together' },
  );
  assertEquals(
    validateSubmissionContact(undefined, '010-1234-5678'),
    { error: 'contact_name and contact_value must be provided together' },
  );
});

Deno.test('담당자 정보는 공백을 정리하고 길이를 제한한다', () => {
  assertEquals(
    validateSubmissionContact(' 홍길동 ', ' 010-1234-5678 '),
    { value: { contactName: '홍길동', contactValue: '010-1234-5678' } },
  );
  assertEquals(
    validateSubmissionContact('가'.repeat(101), '010-1234-5678'),
    { error: 'contact_name must be 100 characters or fewer' },
  );
  assertEquals(
    validateSubmissionContact('홍길동', 'a'.repeat(201)),
    { error: 'contact_value must be 200 characters or fewer' },
  );
});
