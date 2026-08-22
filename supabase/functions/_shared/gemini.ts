/**
 * Gemini Generative Language API 클라이언트.
 *
 * REST 직접 호출. SSE 스트리밍은 streamGenerateContent 엔드포인트를 사용한다.
 * https://ai.google.dev/api/rest/v1beta/models/streamGenerateContent
 *
 * 비용 절감 정책 (Day 1, 2026-05-20):
 *  - Google Search grounding 사용 안 함 (백엔드 강제 OFF).
 *  - thinkingBudget 항상 0 — Flash-Lite 는 RAG/템플릿 답변에 thinking 불필요.
 *  - 외부 검색 citation 미수신. DB 기반 citation 은 호출 측(chat/index.ts)에서 처리.
 */

const MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.1-flash-lite';
export const GEMINI_MODEL = MODEL;

function apiKey(): string {
  const k = Deno.env.get('GEMINI_API_KEY');
  if (!k) throw new Error('GEMINI_API_KEY not set');
  return k;
}

export interface ChatPart {
  text: string;
}

export interface ChatTurn {
  role: 'user' | 'model';
  parts: ChatPart[];
}

export interface GenerateOptions {
  systemInstruction?: string;
  temperature?: number;
  maxOutputTokens?: number;
}

export interface GeminiUsage {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
}

export interface StreamEvent {
  type: 'text' | 'done' | 'error' | 'blocked';
  text?: string;
  error?: string;
  blockReason?: string;
  /** 'done' 이벤트에만 실림. SSE 마지막 청크의 usageMetadata. */
  usage?: GeminiUsage;
}

export const CHAT_SAFETY_SETTINGS = [
  {
    category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    threshold: 'BLOCK_LOW_AND_ABOVE',
  },
  {
    category: 'HARM_CATEGORY_HARASSMENT',
    threshold: 'BLOCK_MEDIUM_AND_ABOVE',
  },
  {
    category: 'HARM_CATEGORY_HATE_SPEECH',
    threshold: 'BLOCK_MEDIUM_AND_ABOVE',
  },
  {
    category: 'HARM_CATEGORY_DANGEROUS_CONTENT',
    threshold: 'BLOCK_MEDIUM_AND_ABOVE',
  },
] as const;

interface ParsedGeminiStreamChunk {
  text: string;
  usage?: GeminiUsage;
  blockReason?: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseUsage(value: unknown): GeminiUsage | undefined {
  if (!isRecord(value)) return undefined;
  const usage: GeminiUsage = {};
  if (typeof value.promptTokenCount === 'number') {
    usage.promptTokenCount = value.promptTokenCount;
  }
  if (typeof value.candidatesTokenCount === 'number') {
    usage.candidatesTokenCount = value.candidatesTokenCount;
  }
  if (typeof value.totalTokenCount === 'number') {
    usage.totalTokenCount = value.totalTokenCount;
  }
  return usage;
}

/** Gemini SSE JSON 한 청크를 외부 JSON 경계에서 즉시 좁힌다. */
export function parseGeminiStreamChunk(value: unknown): ParsedGeminiStreamChunk {
  if (!isRecord(value)) return { text: '' };

  const usage = parseUsage(value.usageMetadata);
  const promptFeedback = isRecord(value.promptFeedback) ? value.promptFeedback : null;
  const promptBlockReason = typeof promptFeedback?.blockReason === 'string'
    ? promptFeedback.blockReason
    : null;

  const candidates = Array.isArray(value.candidates) ? value.candidates : [];
  const candidate = isRecord(candidates[0]) ? candidates[0] : null;
  const finishReason = typeof candidate?.finishReason === 'string' ? candidate.finishReason : null;
  const blockReason = promptBlockReason && promptBlockReason !== 'BLOCK_REASON_UNSPECIFIED'
    ? promptBlockReason
    : finishReason === 'SAFETY'
    ? finishReason
    : undefined;
  if (blockReason) {
    return usage ? { text: '', usage, blockReason } : { text: '', blockReason };
  }

  const content = isRecord(candidate?.content) ? candidate.content : null;
  const parts = Array.isArray(content?.parts) ? content.parts : [];
  const text = parts
    .filter((part) => isRecord(part) && part.thought !== true)
    .map((part) => isRecord(part) && typeof part.text === 'string' ? part.text : '')
    .join('');
  return usage ? { text, usage } : { text };
}

/**
 * 스트리밍 generate.
 * AsyncGenerator 로 텍스트 청크를 순차 yield 한다.
 */
export async function* streamChat(
  history: ChatTurn[],
  opts: GenerateOptions = {},
): AsyncGenerator<StreamEvent> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:streamGenerateContent?alt=sse`;

  const body: Record<string, unknown> = {
    contents: history,
    safetySettings: CHAT_SAFETY_SETTINGS,
    generationConfig: {
      temperature: opts.temperature ?? 0.2,
      maxOutputTokens: opts.maxOutputTokens ?? 2048,
      // thinking 항상 비활성 — grounding 제거 이후 빈 응답 케이스도 사라짐.
      // thought=true 파트는 아래 reader 루프에서 필터링해 채팅엔 노출 안 됨.
      thinkingConfig: { thinkingBudget: 0 },
    },
  };
  if (opts.systemInstruction) {
    body.systemInstruction = { parts: [{ text: opts.systemInstruction }] };
  }

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey() },
    body: JSON.stringify(body),
  });

  if (!res.ok || !res.body) {
    const err = await res.text();
    console.error(`Gemini API error ${res.status}:`, err);
    yield { type: 'error', error: 'AI 응답을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.' };
    return;
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let capturedUsage: GeminiUsage | undefined;
  let safetyBlockEmitted = false;

  // SSE 청크 처리를 한 곳에 (마지막 buffer 잔여 처리에도 재사용)
  function* parseLine(line: string): Generator<StreamEvent> {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return;
    const json = trimmed.slice(5).trim();
    if (!json) return;
    try {
      const parsed = parseGeminiStreamChunk(JSON.parse(json) as unknown);
      if (parsed.usage) capturedUsage = parsed.usage;
      if (parsed.blockReason && !safetyBlockEmitted) {
        safetyBlockEmitted = true;
        yield {
          type: 'blocked',
          error: '안전 정책상 이 내용은 답변할 수 없습니다.',
          blockReason: parsed.blockReason,
        };
        return;
      }
      if (parsed.text) yield { type: 'text', text: parsed.text };
    } catch (_) {
      // 일부 청크가 깨질 수 있으므로 무시
    }
  }

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      // Gemini SSE가 마지막 청크를 종결자(\n\n) 없이 보낼 수 있으므로 잔여 buffer 도 처리
      if (buffer.trim()) {
        for (const ev of parseLine(buffer)) yield ev;
      }
      break;
    }
    buffer += decoder.decode(value, { stream: true });

    // SSE 이벤트 경계는 CRLF 또는 LF 둘 다 허용
    const events = buffer.split(/\r?\n\r?\n/);
    buffer = events.pop() ?? '';

    for (const evt of events) {
      for (const ev of parseLine(evt)) yield ev;
    }
  }
  yield { type: 'done', usage: capturedUsage };
}

export function parseStructuredResponse<T>(json: unknown): T {
  const j = json as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
  const text = j.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
  if (!text) throw new Error('Gemini structured: empty response');
  return JSON.parse(text) as T;
}

export async function generateStructured<T>(
  prompt: string,
  responseSchema: Record<string, unknown>,
  opts: { systemInstruction?: string; temperature?: number; maxOutputTokens?: number } = {},
): Promise<T> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
  const body: Record<string, unknown> = {
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: opts.temperature ?? 0.1,
      maxOutputTokens: opts.maxOutputTokens ?? 4096,
      thinkingConfig: { thinkingBudget: 0 },
      responseMimeType: 'application/json',
      responseSchema,
    },
  };
  if (opts.systemInstruction) {
    body.systemInstruction = { parts: [{ text: opts.systemInstruction }] };
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey() },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  return parseStructuredResponse<T>(await res.json());
}
