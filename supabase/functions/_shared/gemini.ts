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

export interface StreamEvent {
  type: 'text' | 'done' | 'error';
  text?: string;
  error?: string;
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
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:streamGenerateContent?alt=sse&key=${apiKey()}`;

  const body: Record<string, unknown> = {
    contents: history,
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
    headers: { 'Content-Type': 'application/json' },
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

  // SSE 청크 처리를 한 곳에 (마지막 buffer 잔여 처리에도 재사용)
  function* parseLine(line: string): Generator<StreamEvent> {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return;
    const json = trimmed.slice(5).trim();
    if (!json) return;
    try {
      const parsed = JSON.parse(json);
      const candidate = parsed.candidates?.[0];
      const text = candidate?.content?.parts
        ?.filter((p: Record<string, unknown>) => !p.thought)
        .map((p: ChatPart) => p.text)
        .join('') ?? '';
      if (text) yield { type: 'text', text };
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
  yield { type: 'done' };
}
