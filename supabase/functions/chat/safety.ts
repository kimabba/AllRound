/**
 * 채팅 입력의 1차 안전 가드.
 *
 * Gemini 호출 전 명백한 성적·모욕적·위험 요청만 막아 원문을 DB나 외부 AI로
 * 보내지 않는다. 이 목록을 범용 의미 분류기로 착각하면 안 된다. 문맥이 필요한
 * 나머지는 Gemini 안전 필터가 맡고, 여기서는 스포츠 문장의 정상 단어(성적,
 * 성인부, 폭발력, 상대를 이기는 법)를 오탐하지 않는 쪽을 우선한다.
 */

export type ChatSafetyCategory = 'sexual' | 'abusive' | 'dangerous';

export interface ChatSafetyDecision {
  blocked: boolean;
  category?: ChatSafetyCategory;
  responseText?: string;
}

const BLOCK_RESPONSES: Record<ChatSafetyCategory, string> = {
  sexual:
    '성적으로 노골적인 내용은 답변할 수 없어요. 대회·클럽·운동이나 앱 사용에 관해 질문해 주세요.',
  abusive:
    '욕설·모욕·혐오 표현이 포함된 요청은 답변할 수 없어요. 서로 존중하는 표현으로 다시 질문해 주세요.',
  dangerous:
    '사람을 해치거나 위험한 행동을 돕는 요청은 답변할 수 없어요. 지금 즉각적인 위험이 있다면 112 또는 119에 도움을 요청해 주세요.',
};

function compactForSafety(input: string): string {
  return input
    .normalize('NFKC')
    .toLocaleLowerCase('ko-KR')
    .replace(/[\s._*~\-]+/g, '');
}

const SEXUAL_PATTERN = /(섹스|성관계|자위|포르노|야동|음란|누드|나체|강간|성폭행|좆)/i;
const ENGLISH_SEXUAL_PATTERN = /\b(porn(?:o)?|nude|rape)\b/i;
const ABUSIVE_PATTERN =
  /(씨발|시발(?!점)|ㅅㅂ|병신|개새끼|개색끼|(?:너|니가|넌).{0,3}꺼져|꺼져(?:라|버려)|죽어버려)/i;
const DANGEROUS_PATTERN =
  /(폭탄.{0,8}(만들|제조)|사람.{0,8}(죽이|살해)|살해.{0,8}방법|자살.{0,8}방법|마약.{0,8}(만들|제조)|해킹.{0,8}방법|불.{0,5}지르)/i;

export function assessChatInput(input: string): ChatSafetyDecision {
  const compact = compactForSafety(input);
  const normalized = input.normalize('NFKC').toLocaleLowerCase('ko-KR');
  const category: ChatSafetyCategory | null =
    SEXUAL_PATTERN.test(compact) || ENGLISH_SEXUAL_PATTERN.test(normalized)
      ? 'sexual'
      : ABUSIVE_PATTERN.test(compact)
      ? 'abusive'
      : DANGEROUS_PATTERN.test(compact)
      ? 'dangerous'
      : null;

  if (!category) return { blocked: false };
  return {
    blocked: true,
    category,
    responseText: BLOCK_RESPONSES[category],
  };
}

export const GEMINI_SAFETY_REFUSAL =
  '안전 정책상 이 내용은 답변할 수 없어요. 대회·클럽·운동이나 앱 사용에 관한 질문으로 바꿔 주세요.';
