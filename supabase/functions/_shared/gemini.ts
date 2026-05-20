/**
 * Gemini Generative Language API + Search Grounding 클라이언트.
 *
 * REST 직접 호출. SSE 스트리밍은 streamGenerateContent 엔드포인트를 사용한다.
 * https://ai.google.dev/api/rest/v1beta/models/streamGenerateContent
 */

const MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash';

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
  enableSearch?: boolean;
  temperature?: number;
  maxOutputTokens?: number;
}

interface Citation {
  uri?: string;
  title?: string;
}

export interface StreamEvent {
  type: 'text' | 'citation' | 'done' | 'error';
  text?: string;
  citations?: Citation[];
  error?: string;
}

/**
 * 스트리밍 generate.
 * AsyncGenerator 로 텍스트 청크와 인용을 순차 yield 한다.
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
      temperature: opts.temperature ?? 0.4,
      maxOutputTokens: opts.maxOutputTokens ?? 2048,
      // thinking: search grounding 활성 시에는 thinking 일정량이 필요하므로 0으로 강제하지 않음
      //  (강제 0 + search ON + 복잡한 prompt 조합에서 빈 응답 나오는 케이스 발생).
      //  thought=true 파트는 아래 reader 루프에서 필터링해 채팅엔 노출 안 됨.
      thinkingConfig: opts.enableSearch ? undefined : { thinkingBudget: 0 },
    },
  };
  if (opts.systemInstruction) {
    body.systemInstruction = { parts: [{ text: opts.systemInstruction }] };
  }
  if (opts.enableSearch) {
    body.tools = [{ googleSearch: {} }];
  }

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok || !res.body) {
    const err = await res.text();
    yield { type: 'error', error: `Gemini error ${res.status}: ${err}` };
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

      const grounding = candidate?.groundingMetadata?.groundingChunks;
      if (grounding) {
        const citations: Citation[] = grounding
          .map((c: { web?: Citation }) => c.web)
          .filter(Boolean);
        if (citations.length) yield { type: 'citation', citations };
      }
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
