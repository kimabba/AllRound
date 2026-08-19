import { assert, assertEquals, assertStringIncludes } from 'std/assert/mod.ts';
import {
  buildTournamentSubmissionEmail,
  recipientEnvKeyForSport,
  sendTournamentSubmissionEmail,
  type TournamentSubmissionEmailInput,
} from '../_shared/tournament_submission_email.ts';

const input: TournamentSubmissionEmailInput = {
  tournamentId: '11111111-2222-4333-8444-555555555555',
  sport: 'tennis',
  title: '광주 오픈\n테니스 대회',
  organizer: '광주협회',
  startDate: '2026-09-01',
  region: '광주',
  location: '진월국제테니스장',
  sourceUrl: 'https://example.com/tournament',
  contactName: '홍길동',
  contactValue: '010-1234-5678',
};

function configuredEnv(key: string): string | undefined {
  const values: Record<string, string> = {
    RESEND_API_KEY: 're_test_key',
    TOURNAMENT_SUBMISSION_EMAIL_FROM: 'AllRound <noreply@example.com>',
    TOURNAMENT_SUBMISSION_TENNIS_EMAIL: 'junmo@example.com',
    TOURNAMENT_SUBMISSION_FUTSAL_EMAIL: 'juhee@example.com',
  };
  return values[key];
}

Deno.test('종목별 대회 제보 메일 수신 설정을 준모와 주희로 분리한다', () => {
  assertEquals(
    recipientEnvKeyForSport('tennis'),
    'TOURNAMENT_SUBMISSION_TENNIS_EMAIL',
  );
  assertEquals(
    recipientEnvKeyForSport('futsal'),
    'TOURNAMENT_SUBMISSION_FUTSAL_EMAIL',
  );
});

Deno.test('대회 제보 메일에 담당자 정보와 검수 내용을 담는다', () => {
  const message = buildTournamentSubmissionEmail(input, 'junmo@example.com');
  assertEquals(message.recipient, 'junmo@example.com');
  assertEquals(
    message.subject,
    '[올라운드][테니스] 새 대회 제보: 광주 오픈 테니스 대회',
  );
  assertStringIncludes(message.text, '담당자: 홍길동');
  assertStringIncludes(message.text, '연락처: 010-1234-5678');
  assertStringIncludes(message.text, '원본 공고: https://example.com/tournament');
});

Deno.test('테니스와 풋살 제보를 각 담당자 주소로 발송한다', async () => {
  const recipients: string[] = [];
  const fetcher = (
    _request: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const parsed: unknown = JSON.parse(String(init?.body ?? ''));
    assert(typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed));
    const to = (parsed as Record<string, unknown>).to;
    assert(Array.isArray(to) && typeof to[0] === 'string');
    recipients.push(to[0]);
    return Promise.resolve(new Response('{"id":"email-id"}', { status: 200 }));
  };

  assertEquals(
    await sendTournamentSubmissionEmail(input, { getEnv: configuredEnv, fetcher }),
    { status: 'sent' },
  );
  assertEquals(
    await sendTournamentSubmissionEmail(
      { ...input, sport: 'futsal' },
      { getEnv: configuredEnv, fetcher },
    ),
    { status: 'sent' },
  );
  assertEquals(recipients, ['junmo@example.com', 'juhee@example.com']);
});

Deno.test('메일 설정이 없으면 외부 요청 없이 제보 저장 경로를 계속 진행한다', async () => {
  let called = false;
  const result = await sendTournamentSubmissionEmail(input, {
    getEnv: () => undefined,
    fetcher: (): Promise<Response> => {
      called = true;
      return Promise.resolve(new Response(null, { status: 200 }));
    },
  });
  assertEquals(result, { status: 'skipped', reason: 'missing_api_key' });
  assertEquals(called, false);
});
