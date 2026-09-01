import { type Sport, SPORT_LABELS } from './enums.ts';

const resendEndpoint = 'https://api.resend.com/emails';

type GetEnv = (key: string) => string | undefined;
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export interface TournamentSubmissionEmailInput {
  tournamentId: string;
  sport: Sport;
  title: string;
  organizer?: string | null;
  startDate: string;
  region?: string | null;
  location?: string | null;
  sourceUrl?: string | null;
  contactName?: string | null;
  contactValue?: string | null;
}

export interface TournamentSubmissionEmailMessage {
  recipient: string;
  subject: string;
  text: string;
}

export type TournamentSubmissionEmailResult =
  | { status: 'sent' }
  | {
    status: 'skipped';
    reason: 'missing_api_key' | 'missing_sender' | 'missing_recipient';
  }
  | { status: 'failed'; reason: 'network_error' | `provider_${number}` };

export interface TournamentSubmissionEmailOptions {
  getEnv?: GetEnv;
  fetcher?: Fetcher;
}

export function recipientEnvKeyForSport(sport: Sport): string {
  return sport === 'tennis'
    ? 'TOURNAMENT_SUBMISSION_TENNIS_EMAIL'
    : 'TOURNAMENT_SUBMISSION_FUTSAL_EMAIL';
}

function oneLine(value: string): string {
  return value.replace(/[\r\n]+/g, ' ').trim();
}

function optionalValue(value: string | null | undefined): string {
  const trimmed = value?.trim() ?? '';
  return trimmed.length > 0 ? trimmed : '미입력';
}

export function buildTournamentSubmissionEmail(
  input: TournamentSubmissionEmailInput,
  recipient: string,
): TournamentSubmissionEmailMessage {
  const label = SPORT_LABELS[input.sport];
  const safeTitle = oneLine(input.title);
  return {
    recipient,
    subject: `[올라운드][${label}] 새 대회 제보: ${safeTitle}`,
    text: [
      '새로운 대회 등록 문의가 접수되었습니다.',
      '',
      `종목: ${label}`,
      `대회명: ${safeTitle}`,
      `주최: ${optionalValue(input.organizer)}`,
      `시작일: ${input.startDate}`,
      `지역: ${optionalValue(input.region)}`,
      `장소: ${optionalValue(input.location)}`,
      `담당자: ${optionalValue(input.contactName)}`,
      `연락처: ${optionalValue(input.contactValue)}`,
      `원본 공고: ${optionalValue(input.sourceUrl)}`,
      '',
      `대회 ID: ${input.tournamentId}`,
      '관리자 대회 검수 화면에서 내용을 확인해 주세요.',
    ].join('\n'),
  };
}

export async function sendTournamentSubmissionEmail(
  input: TournamentSubmissionEmailInput,
  options: TournamentSubmissionEmailOptions = {},
): Promise<TournamentSubmissionEmailResult> {
  const getEnv = options.getEnv ?? ((key: string): string | undefined => Deno.env.get(key));
  const fetcher = options.fetcher ?? fetch;
  const apiKey = getEnv('RESEND_API_KEY')?.trim() ?? '';
  if (apiKey.length === 0) return { status: 'skipped', reason: 'missing_api_key' };

  const sender = getEnv('TOURNAMENT_SUBMISSION_EMAIL_FROM')?.trim() ?? '';
  if (sender.length === 0) return { status: 'skipped', reason: 'missing_sender' };

  const recipient = getEnv(recipientEnvKeyForSport(input.sport))?.trim() ?? '';
  if (recipient.length === 0) return { status: 'skipped', reason: 'missing_recipient' };

  const message = buildTournamentSubmissionEmail(input, recipient);
  let response: Response;
  try {
    response = await fetcher(resendEndpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': `tournament-submission-${input.tournamentId}`,
        'User-Agent': 'allround-tournament-submit/1.0',
      },
      signal: AbortSignal.timeout(5000),
      body: JSON.stringify({
        from: sender,
        to: [message.recipient],
        subject: message.subject,
        text: message.text,
      }),
    });
  } catch {
    return { status: 'failed', reason: 'network_error' };
  }

  if (!response.ok) {
    return { status: 'failed', reason: `provider_${response.status}` };
  }
  return { status: 'sent' };
}
