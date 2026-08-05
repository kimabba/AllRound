import { errorResponse, jsonResponse, preflight, withCors } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';

/**
 * GET /chat-history?conversation_id=...&limit=50
 *  → conversation_id 가 있으면 그 대화의 메시지, 없으면 최근 conversation 목록
 *
 * DELETE /chat-history?conversation_id=...   본인 대화만 삭제 가능
 */
Deno.serve(withCors(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  const url = new URL(req.url);
  const conversationId = url.searchParams.get('conversation_id');

  if (req.method === 'DELETE') {
    if (!conversationId) return errorResponse('conversation_id required');
    const { error } = await supabase
      .from('chat_messages')
      .delete()
      .eq('user_id', user.id)
      .eq('conversation_id', conversationId);
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ ok: true });
  }

  if (req.method !== 'GET') return errorResponse('Method not allowed', 405);

  if (conversationId) {
    const limit = Math.min(parseInt(url.searchParams.get('limit') ?? '100', 10), 500);
    const { data, error } = await supabase
      .from('chat_messages')
      .select('id, role, content, citations, metadata, created_at')
      .eq('user_id', user.id)
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true })
      .limit(limit);
    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ messages: data ?? [] });
  }

  // 최근 conversation 목록 (id, 마지막 user 메시지 미리보기)
  const { data, error } = await supabase
    .from('chat_messages')
    .select('conversation_id, content, role, created_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) return errorResponse(error.message, 500);

  // conversation_id 별 첫 사용자 메시지로 미리보기 만들기
  const seen = new Set<string>();
  const conversations: { id: string; preview: string; last_at: string }[] = [];
  for (const m of (data ?? [])) {
    if (seen.has(m.conversation_id)) continue;
    seen.add(m.conversation_id);
    conversations.push({
      id: m.conversation_id,
      preview: m.content.slice(0, 80),
      last_at: m.created_at,
    });
  }

  return jsonResponse({ conversations });
}));
