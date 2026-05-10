import { corsHeaders, errorResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { embedText, toVectorLiteral } from '../_shared/embedding.ts';
import { ChatTurn, streamChat } from '../_shared/gemini.ts';
import {
  GRADE_LABELS,
  REGION_LABELS,
  SPORT_LABELS,
  TENNIS_ORG_LABELS,
} from '../_shared/enums.ts';

/**
 * POST /chat
 * Body: { message: string, conversation_id?: string, enable_search?: boolean }
 *
 * SSE 스트리밍 응답.
 *  event: meta       → { conversation_id }
 *  event: context    → { tournaments: [...], rules: [...] }   (RAG 결과)
 *  event: delta      → { text: '...' }
 *  event: citation   → { items: [{title, url}] }
 *  event: done       → {}
 *
 * 흐름: 사용자 컨텍스트 + RAG 결과 + Search Grounding 을 결합한 답변.
 */
interface ChatBody {
  message: string;
  conversation_id?: string;
  enable_search?: boolean;
}

interface UserSport {
  sport: string;
  grade: string;
}

interface UserTennisOrgRow {
  org: string;
  division_local: string | null;
  score: number | null;
  is_primary: boolean;
  region_code: string | null;
}

interface SemanticTournament {
  id: string;
  sport: string;
  title: string;
  start_date: string;
  region: string | null;
  eligible_grades: string[];
  similarity: number;
}

interface SemanticRule {
  id: string;
  sport: string;
  category: string;
  title: string;
  body: string;
  similarity: number;
}

function sseEvent(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function buildSystemPrompt(sports: UserSport[], orgs: UserTennisOrgRow[]): string {
  const profile = sports.length === 0
    ? '아직 종목·등급을 등록하지 않았습니다.'
    : sports
      .map((s) =>
        `- ${SPORT_LABELS[s.sport as 'tennis' | 'futsal'] ?? s.sport}: ${
          GRADE_LABELS[s.grade] ?? s.grade
        }`
      )
      .join('\n');

  const orgProfile = orgs.length === 0
    ? ''
    : '\n\n[등록 협회 (테니스, 다중 등록 가능)]\n' + orgs.map((o) => {
      const orgName = TENNIS_ORG_LABELS[o.org as keyof typeof TENNIS_ORG_LABELS] ?? o.org;
      const division = o.division_local ?? '미입력';
      const score = o.score !== null ? ` (점수 ${o.score})` : '';
      const primary = o.is_primary ? ' ★주' : '';
      const region = o.region_code
        ? ` [${REGION_LABELS[o.region_code as keyof typeof REGION_LABELS] ?? o.region_code}]`
        : '';
      return `- ${orgName}: ${division}${score}${primary}${region}`;
    }).join('\n');

  return `당신은 한국 동호인 테니스/풋살 정보 도우미입니다. 사용자의 등록 종목·등급·협회를 고려해 답변하세요.

[사용자 프로필]
${profile}${orgProfile}

[규칙]
- 한국어로 답변합니다.
- 대회 추천 시 사용자가 출전 가능한 등급·협회의 대회를 우선 추천합니다.
- 한국에는 KTA·KATO·KATA·KTFS 등 여러 협회가 있고 등급 체계가 다릅니다. 사용자의 등록 협회를 우선 고려.
- 광주·전남은 2026.05.01자로 분리 운영 중입니다 (이중 등록 허용).
- DB에서 제공된 [관련 대회], [관련 룰] 컨텍스트가 있으면 이를 우선 인용합니다.
- DB에 정보가 없거나 최신성이 필요하면 웹 검색 결과를 활용합니다.
- 출처는 DB id 또는 웹 URL 로 명시합니다.
- 모르는 것은 모른다고 답합니다.
- 의료/법적 조언은 하지 않습니다.`;
}

function buildContextPrompt(
  tournaments: SemanticTournament[],
  rules: SemanticRule[],
): string {
  const parts: string[] = [];

  if (tournaments.length > 0) {
    parts.push('[관련 대회]');
    for (const t of tournaments.slice(0, 5)) {
      parts.push(
        `- (id: ${t.id}) ${t.title} | ${t.sport} | ${t.start_date} | ${
          t.region ?? '지역미상'
        } | 출전등급: ${t.eligible_grades.join(', ')}`,
      );
    }
  }

  if (rules.length > 0) {
    parts.push('\n[관련 룰북]');
    for (const r of rules.slice(0, 3)) {
      const snippet = r.body.length > 300 ? r.body.slice(0, 300) + '…' : r.body;
      parts.push(`- (id: ${r.id}) [${r.sport}/${r.category}] ${r.title}\n  ${snippet}`);
    }
  }

  return parts.join('\n');
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: ChatBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.message?.trim()) return errorResponse('message required');

  const conversationId = body.conversation_id ?? crypto.randomUUID();
  const userMessage = body.message.trim();

  // 사용자 종목·등급
  const { data: userSports } = await supabase
    .from('user_sports')
    .select('sport, grade')
    .eq('user_id', user.id);

  // 사용자 등록 협회 (multi-org)
  const { data: userOrgs } = await supabase
    .from('user_tennis_orgs')
    .select('org, division_local, score, is_primary, region_code')
    .eq('user_id', user.id);

  // 이전 대화 (최근 10턴)
  const { data: prior } = await supabase
    .from('chat_messages')
    .select('role, content')
    .eq('user_id', user.id)
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true })
    .limit(20);

  // 사용자 메시지 영구 저장
  await supabase.from('chat_messages').insert({
    user_id: user.id,
    conversation_id: conversationId,
    role: 'user',
    content: userMessage,
  });

  const stream = new ReadableStream({
    async start(controller) {
      const encoder = new TextEncoder();
      const send = (event: string, data: unknown) => {
        controller.enqueue(encoder.encode(sseEvent(event, data)));
      };

      try {
        send('meta', { conversation_id: conversationId });

        // ---- RAG ----
        let tournaments: SemanticTournament[] = [];
        let rules: SemanticRule[] = [];
        try {
          const queryEmbedding = await embedText(userMessage, 'RETRIEVAL_QUERY');
          const literal = toVectorLiteral(queryEmbedding);

          const [tRes, rRes] = await Promise.all([
            supabase.rpc('tournaments_semantic_search', {
              p_user_id: user.id,
              p_query_embedding: literal,
              p_only_my_grade: true,
              p_match_count: 5,
            }),
            supabase.rpc('rules_semantic_search', {
              p_query_embedding: literal,
              p_sport: null,
              p_match_count: 3,
            }),
          ]);

          tournaments = (tRes.data as SemanticTournament[]) ?? [];
          rules = (rRes.data as SemanticRule[]) ?? [];
          send('context', { tournaments, rules });
        } catch (e) {
          // RAG 실패해도 답변은 진행
          console.error('RAG failed:', (e as Error).message);
        }

        // ---- Gemini 호출 ----
        const systemPrompt = buildSystemPrompt(
          userSports ?? [],
          (userOrgs ?? []) as UserTennisOrgRow[],
        );
        const contextPrompt = buildContextPrompt(tournaments, rules);

        const history: ChatTurn[] = [];
        for (const m of prior ?? []) {
          history.push({
            role: m.role === 'assistant' ? 'model' : 'user',
            parts: [{ text: m.content }],
          });
        }
        // 컨텍스트는 사용자 메시지 앞에 별도 user 턴으로 주입
        if (contextPrompt) {
          history.push({
            role: 'user',
            parts: [{ text: `다음 컨텍스트를 참고해 답변하세요.\n\n${contextPrompt}` }],
          });
          history.push({
            role: 'model',
            parts: [{ text: '네, 위 컨텍스트를 참고해 답변하겠습니다.' }],
          });
        }
        history.push({ role: 'user', parts: [{ text: userMessage }] });

        let assistantText = '';
        const collectedCitations: { uri?: string; title?: string }[] = [];

        for await (
          const evt of streamChat(history, {
            systemInstruction: systemPrompt,
            enableSearch: body.enable_search ?? true,
          })
        ) {
          if (evt.type === 'text' && evt.text) {
            assistantText += evt.text;
            send('delta', { text: evt.text });
          } else if (evt.type === 'citation' && evt.citations) {
            collectedCitations.push(...evt.citations);
            send('citation', { items: evt.citations });
          } else if (evt.type === 'error') {
            send('error', { message: evt.error });
          }
        }

        // assistant 메시지 영구 저장
        const dbCitations = tournaments.slice(0, 5).map((t) => ({
          type: 'db' as const,
          source: 'tournaments',
          id: t.id,
          title: t.title,
        }));
        const ruleCitations = rules.slice(0, 3).map((r) => ({
          type: 'db' as const,
          source: 'rules',
          id: r.id,
          title: r.title,
        }));
        const webCitations = collectedCitations.map((c) => ({
          type: 'web' as const,
          url: c.uri,
          title: c.title,
        }));

        await supabase.from('chat_messages').insert({
          user_id: user.id,
          conversation_id: conversationId,
          role: 'assistant',
          content: assistantText,
          citations: [...dbCitations, ...ruleCitations, ...webCitations],
        });

        send('done', {});
      } catch (e) {
        send('error', { message: (e as Error).message });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'X-Accel-Buffering': 'no',
    },
  });
});
