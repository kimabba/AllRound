/**
 * Gemini gemini-embedding-001 클라이언트 (Matryoshka, 출력 차원 선택 가능).
 *
 * 우리 DB 스키마는 vector(768) 이므로 outputDimensionality=768 로 고정.
 * 모델명은 GEMINI_EMBEDDING_MODEL 로 오버라이드 가능.
 *
 * https://ai.google.dev/gemini-api/docs/embeddings
 */

const MODEL = Deno.env.get('GEMINI_EMBEDDING_MODEL') ?? 'gemini-embedding-2';
export const EMBEDDING_MODEL = MODEL;
export const EMBEDDING_DIM = 768;

export interface EmbedUsage {
  promptTokenCount?: number;
  totalTokenCount?: number;
}

interface EmbedResponse {
  embedding?: { values: number[] };
  embeddings?: { values: number[] }[];
  usageMetadata?: EmbedUsage;
  error?: { message: string };
}

function apiKey(): string {
  const k = Deno.env.get('GEMINI_API_KEY');
  if (!k) throw new Error('GEMINI_API_KEY not set');
  return k;
}

/**
 * 단일 텍스트 임베딩 + usageMetadata(있으면).
 */
export async function embedTextWithUsage(
  text: string,
  taskType = 'RETRIEVAL_DOCUMENT',
): Promise<{ values: number[]; usage?: EmbedUsage }> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:embedContent?key=${apiKey()}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: `models/${MODEL}`,
      content: { parts: [{ text }] },
      taskType,
      outputDimensionality: EMBEDDING_DIM,
    }),
  });
  const data: EmbedResponse = await res.json();
  if (!res.ok || !data.embedding?.values) {
    throw new Error(`embedText failed: ${data.error?.message ?? res.status}`);
  }
  return { values: data.embedding.values, usage: data.usageMetadata };
}

/**
 * 단일 텍스트 임베딩.
 */
export async function embedText(text: string, taskType = 'RETRIEVAL_DOCUMENT'): Promise<number[]> {
  return (await embedTextWithUsage(text, taskType)).values;
}

/**
 * 배치 임베딩. 호출 비용 절감용.
 */
export async function embedBatch(
  texts: string[],
  taskType = 'RETRIEVAL_DOCUMENT',
): Promise<number[][]> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:batchEmbedContents?key=${apiKey()}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      requests: texts.map((text) => ({
        model: `models/${MODEL}`,
        content: { parts: [{ text }] },
        taskType,
        outputDimensionality: EMBEDDING_DIM,
      })),
    }),
  });
  const data: EmbedResponse = await res.json();
  if (!res.ok || !data.embeddings) {
    throw new Error(`embedBatch failed: ${data.error?.message ?? res.status}`);
  }
  return data.embeddings.map((e) => e.values);
}

/**
 * pgvector 가 받는 문자열 포맷으로 변환.
 * '[0.1, 0.2, ...]' 형태.
 */
export function toVectorLiteral(values: number[]): string {
  return `[${values.join(',')}]`;
}
