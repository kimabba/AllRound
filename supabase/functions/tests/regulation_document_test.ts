import { assertEquals } from 'std/assert/mod.ts';
import {
  mergeRegulationDocuments,
  normalizeRegulationDocument,
  regulationDocumentFromLegacy,
  regulationDocumentToBody,
  regulationDocumentToFields,
  regulationDocumentVerificationFields,
  sectionCodeForLegacyLabel,
} from '../_shared/regulation_document.ts';

Deno.test('normalizeRegulationDocument: 섹션을 고정 순서로 정렬하고 잘못된 블록은 제거', () => {
  const document = normalizeRegulationDocument({
    schema_version: 1,
    summary: '  테스트 요강  ',
    sections: [
      {
        code: 'awards',
        availability: 'present',
        blocks: [{ type: 'paragraph', text: '우승 30만원' }],
      },
      {
        code: 'eligibility',
        availability: 'present',
        blocks: [{ type: 'bullets', items: ['광주협회 등록 회원', ' '] }],
      },
      { code: 'unknown', availability: 'present', blocks: [] },
    ],
  });

  assertEquals(document?.summary, '테스트 요강');
  assertEquals(document?.sections.map((section) => section.code), ['eligibility', 'awards']);
  assertEquals(document?.sections[0].blocks[0].items, ['광주협회 등록 회원']);
});

Deno.test('normalizeRegulationDocument: present 빈 섹션은 버리고 공지 전 상태는 보존', () => {
  const document = normalizeRegulationDocument({
    schema_version: 1,
    sections: [
      { code: 'eligibility', availability: 'present', blocks: [] },
      { code: 'schedule_venue', availability: 'not_announced', blocks: [] },
    ],
  });
  assertEquals(document?.sections, [{
    code: 'schedule_venue',
    availability: 'not_announced',
    blocks: [],
  }]);
});

Deno.test('legacy 라벨을 공통 섹션 코드로 정규화', () => {
  assertEquals(sectionCodeForLegacyLabel('참가신청 기간'), 'registration_payment');
  assertEquals(sectionCodeForLegacyLabel('남자 일반부 입금계좌'), 'registration_payment');
  assertEquals(sectionCodeForLegacyLabel('부서별 일정·장소'), 'schedule_venue');
  assertEquals(sectionCodeForLegacyLabel('예외부서 규정'), 'eligibility');
  assertEquals(sectionCodeForLegacyLabel('접수·환불'), 'refund_changes');
});

Deno.test('regulationDocumentFromLegacy: 자유 라벨을 고정 섹션과 순서로 그룹화', () => {
  const document = regulationDocumentFromLegacy([
    { label: '시상', value: '우승 30만원' },
    { label: '접수기간', value: '8월 1일~10일' },
    { label: '참가자격', value: '광주협회 등록 회원' },
  ], ['우천 시 일정 변경']);

  assertEquals(document?.sections.map((section) => section.code), [
    'eligibility',
    'registration_payment',
    'awards',
    'notices_contact',
  ]);
  assertEquals(regulationDocumentToFields(document!).map((field) => field.label), [
    '참가자격',
    '접수기간',
    '시상',
  ]);
});

Deno.test('mergeRegulationDocuments: 결정적 파서 섹션을 우선하고 AI 누락 섹션은 보충', () => {
  const deterministic = regulationDocumentFromLegacy([
    { label: '입금계좌', value: '농협 123-456-789' },
  ])!;
  const ai = normalizeRegulationDocument({
    schema_version: 1,
    sections: [
      {
        code: 'registration_payment',
        availability: 'present',
        blocks: [{ type: 'paragraph', text: 'AI 계좌 설명' }],
      },
      {
        code: 'match_operations',
        availability: 'present',
        blocks: [{ type: 'paragraph', text: '예선 조별리그' }],
      },
    ],
  })!;

  const merged = mergeRegulationDocuments(deterministic, ai);
  assertEquals(merged.sections.map((section) => section.code), [
    'registration_payment',
    'match_operations',
  ]);
  assertEquals(merged.sections[0].blocks[0].type, 'key_values');
  assertEquals(regulationDocumentToBody(merged), '● 경기 방식 및 운영\n예선 조별리그');
});

Deno.test('regulationDocumentVerificationFields: 모든 블록 텍스트를 원문 검증 대상으로 평탄화', () => {
  const document = normalizeRegulationDocument({
    schema_version: 1,
    sections: [{
      code: 'registration_payment',
      availability: 'present',
      blocks: [
        { type: 'key_values', entries: [{ label: '참가비', value: '64,000원' }] },
        {
          type: 'division_schedule',
          divisions: [{ name: '일반부', account: '농협 123-456-789' }],
        },
      ],
    }],
  })!;
  const fields = regulationDocumentVerificationFields(document);
  assertEquals(fields[0], { label: '참가비', value: '64,000원' });
  assertEquals(fields[1], {
    label: '신청 및 결제',
    value: '일반부 농협 123-456-789',
  });
});

Deno.test('유의사항 숫자는 문의처 예외 label로 위장하지 않는다', () => {
  const document = normalizeRegulationDocument({
    schema_version: 1,
    sections: [{
      code: 'notices_contact',
      availability: 'present',
      blocks: [
        { type: 'notice', text: '취소 수수료 30,000원' },
        { type: 'key_values', entries: [{ label: '문의처', value: '010-1234-5678' }] },
      ],
    }],
  })!;

  assertEquals(regulationDocumentVerificationFields(document), [
    { label: '유의사항', value: '취소 수수료 30,000원' },
    { label: '문의처', value: '010-1234-5678' },
  ]);
});
