# Chat A2UI Cards Design

## Goal

Make the chatbot a complete place to discover tournament and club information. Users should see structured tournament and club cards inside the chat, then continue with follow-up questions in the same chat instead of navigating to detail screens.

## User Experience

When a user asks for tournaments or clubs, the assistant answers with a short summary and renders cards below the message.

Tournament cards show:
- Title
- Sport
- Region/location
- Date and deadline when available
- Eligibility status from the server
- Key metadata such as division, fee, and format when available

Club cards show:
- Name
- Sport
- Region/address
- Member count when available
- Contact or website when available
- Approval/public status already filtered by the server

Card actions do not navigate away. They send follow-up chat requests such as:
- `상세 알려줘`
- `신청 방법 알려줘`
- `마감 확인해줘`
- `내 등급으로 참가 가능해?`
- `가입 방법 알려줘`
- `비슷한 클럽 더 찾아줘`

The UI must not expose raw database ids to the user.

## Architecture

The chat Edge Function remains the source of truth for search and follow-up context.

Flow:

```text
Flutter ChatScreen
  -> ApiService.chat()
  -> supabase/functions/chat
  -> intent + slots
  -> server/RPC search
  -> SSE delta + ui events
  -> Flutter renders cards in the assistant message
  -> card action sends another chat request with selected_entity context
```

The existing `tournament_search` routing path should be extended rather than replaced. It already uses `tournament_search_by_slots`, which enforces published tournament visibility and same-sport grade eligibility through server-side logic.

The existing `club_search` intent should become routable. It needs a server-side search path that returns only approved/public clubs for normal users. This can be implemented either as a reusable SQL RPC or by sharing validated backend logic with `clubs-search`. The preferred design is a SQL RPC so filtering and pagination rules live close to the database.

## SSE Contract

Keep existing events for compatibility:
- `meta`
- `intent`
- `route`
- `cache`
- `context`
- `delta`
- `citation`
- `done`
- `error`

Add a new event:

```text
event: ui
data: {
  "blocks": [
    {
      "type": "cards",
      "entity": "tournament",
      "items": [...]
    }
  ]
}
```

Card items should use typed, display-safe payloads. They should include ids for client-to-server context, but the UI must not render those ids.

Example tournament item:

```json
{
  "id": "uuid",
  "title": "광주 생활체육 테니스 오픈",
  "sport": "tennis",
  "region": "광주",
  "location": "진월국제테니스장",
  "start_date": "2026-06-13",
  "end_date": "2026-06-13",
  "application_deadline": "2026-06-11",
  "eligible": true,
  "eligible_grades": ["gj_m_gold"],
  "entry_fee": 30000,
  "format": "복식"
}
```

Example club item:

```json
{
  "id": "uuid",
  "name": "광주 테니스 모임",
  "sport": "tennis",
  "region": "광주",
  "address": "광주 ...",
  "member_count": 24,
  "contact": "010-0000-0000",
  "website": null,
  "description": "주말 정기 운동"
}
```

## Follow-Up Context

Card actions should call `ApiService.chat()` again with a structured selection context, not with only a natural-language message.

Request body extension:

```json
{
  "message": "신청 방법 알려줘",
  "conversation_id": "uuid",
  "selected_entity": {
    "type": "tournament",
    "id": "uuid"
  }
}
```

The server must re-check the selected entity before answering:
- Tournament must be visible to the user.
- Tournament eligibility must be recomputed server-side before saying the user can participate.
- Club must be approved/public unless the user is allowed to see it through membership/admin rules.
- The selected entity type must match the table being queried.

The selected entity can be used to fetch deterministic details before falling back to RAG or LLM. If the entity is no longer visible, the assistant should say the information is no longer available.

## Security And Trust Boundaries

Flutter only renders server-approved cards and sends user actions. It must not decide:
- Tournament visibility
- Tournament eligibility
- Club approval/public visibility
- Admin access
- Rate limits or quotas

All authority remains in Edge Functions, SQL/RPC, and RLS.

Retrieved tournament and club text is untrusted data. If it is passed into an LLM prompt, it must be wrapped as data and protected by the existing prompt-injection rules.

## Backend Changes

1. Extend chat request validation.
   - Parse JSON as `unknown`.
   - Validate `message`, `conversation_id`, `active_sport`, and optional `selected_entity`.
   - Reject invalid entity types and malformed ids.

2. Add typed UI block helpers.
   - `ChatUiBlock`
   - `TournamentCardItem`
   - `ClubCardItem`
   - `send('ui', { blocks: [...] })`

3. Extend routable intents.
   - Keep `tournament_search`.
   - Add `club_search` once the server-side search path is ready.

4. Add deterministic detail handling for selected entities.
   - `selected_entity.type === 'tournament'`: fetch visible tournament and answer details from DB fields.
   - `selected_entity.type === 'club'`: fetch visible club and answer details from DB fields.

5. Add club search RPC or equivalent backend helper.
   - Return only approved clubs for normal search.
   - Support sport, region, text query, and limit.
   - Apply filters before pagination.

## Flutter Changes

1. Add typed chat UI models.
   - `ChatUiBlock`
   - `ChatCardItem`
   - `TournamentChatCard`
   - `ClubChatCard`

2. Extend `ChatStreamEvent` handling.
   - On `ui`, parse blocks into typed models.
   - Attach blocks to the current assistant message.

3. Update `_Msg`.
   - Add `uiBlocks`.
   - Keep citations separate.

4. Render cards in `_MessageBubble`.
   - Cards appear under markdown text.
   - Cards use compact, readable mobile-first layout.
   - Actions call a follow-up send method with `selected_entity`.

5. Extend `ApiService.chat()`.
   - Add optional `selectedEntity`.
   - Encode it in the request body.

## Error Handling

If search returns no cards, the assistant should answer with a short empty state instead of rendering an empty card block.

If a selected card is no longer visible, the assistant should answer:

```text
현재 매치업 DB에서 이 항목을 확인할 수 없습니다. 정보가 변경되었거나 접근 권한이 없을 수 있습니다.
```

If card UI parsing fails on Flutter, the markdown answer should still render.

## Testing

Backend:
- Intent routing still handles tournament search.
- Club search intent returns only approved clubs.
- `selected_entity` rejects malformed ids and invalid entity types.
- Tournament detail follow-up does not expose draft tournaments.
- Club detail follow-up does not expose pending/rejected clubs.
- Prompt-injection text in tournament/club descriptions remains data only.

Flutter:
- `ui` SSE event parses into typed card models.
- Tournament and club cards render from sample payloads.
- Card actions send follow-up requests with `selected_entity`.
- Markdown-only chat responses still work.

Relevant checks:

```bash
cd supabase/functions
deno fmt --check */index.ts _shared/*.ts tests/*.ts
deno lint --config deno.json */index.ts _shared/*.ts tests/*.ts
deno check --config deno.json */index.ts _shared/*.ts tests/*.ts
deno test --config deno.json --allow-env --allow-read tests

cd app
flutter analyze
flutter test
```

For migration changes, run:

```bash
supabase db reset
```

## Out Of Scope

This design does not implement:
- Navigating to tournament or club detail screens from chat cards
- Tournament application submission inside chat
- Club join request submission inside chat
- Admin approval workflows inside chat
- External web search or Google grounding

Those can be added later after card rendering and follow-up context are stable.
