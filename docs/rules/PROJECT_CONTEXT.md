# Project Context

Load this when you need product architecture, endpoint map, env vars, or operational behavior.
Do not load it for small style-only edits.

## Overview

**Match-up** is a tennis/futsal community information app.

Users register sports and grades. The app then shows only tournaments they are eligible to enter, plus favorites, push reminders, sport rulebooks, an AI chatbot using Gemini Search Grounding + RAG, and a club directory.

## Tech stack

- **Frontend:** Flutter/Dart for iOS, Android, and web.
- **Backend:** Supabase Edge Functions on Deno. Do not introduce FastAPI for server logic.
- **DB:** Supabase Postgres, pgvector, pg_cron, pg_net.
- **AI:** Gemini API (`gemini-2.0-flash`) + Search Grounding + `gemini-embedding-001` 768d RAG embeddings.
- **Auth:** Supabase Auth via email/Google, Kakao later.
- **Push:** Firebase Cloud Messaging.
- **Streaming:** SSE for chatbot responses.

## Architecture

```text
Flutter App
  ├── Supabase Auth
  ├── REST + SSE → Edge Functions (Deno)
  │     ├── tournaments-search / tournaments-submit / tournaments-approve
  │     ├── clubs-search
  │     ├── chat / chat-history / semantic-search
  │     ├── embed-pending / notify-cron
  │     ├── crawl-tennis-gwangju / crawl-tennis-jeonnam / crawl-tennis-korea
  │     └── health
  ├── Postgres
  │     ├── users / user_sports
  │     ├── tournaments / tournament_favorites
  │     ├── clubs
  │     ├── chat_messages / rule_articles
  │     ├── device_tokens / notifications_log
  │     └── crawl_audit
  └── FCM
```

## Edge Function endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/tournaments-search` | user | Grade-aware tournament search. |
| POST | `/tournaments-submit` | user | User submission, initially `draft`. |
| POST | `/tournaments-approve` | admin | Approve/reject submissions. |
| GET | `/clubs-search` | user | Club directory search. |
| POST | `/chat` | user | SSE chatbot using RAG + Search Grounding. |
| GET/DELETE | `/chat-history` | user | Chat history. |
| POST | `/semantic-search` | user | pgvector semantic search. |
| POST | `/embed-pending` | cron | Embedding worker, `verify_jwt=false`. |
| POST | `/notify-cron` | cron | D-3/deadline notification worker, `verify_jwt=false`. |
| POST | `/crawl-tennis-*` | cron | Tennis crawlers, `verify_jwt=false`. |
| GET | `/health` | none | Health check. |

## Key paths

### Supabase

- `supabase/migrations/*.sql` — schema, RLS, RPC, cron.
- `supabase/functions/_shared/*.ts` — shared Deno helpers.
- `supabase/functions/<name>/index.ts` — Edge Function entrypoints.
- `supabase/seed.sql` — rulebook and club seed data.

### Flutter

- `app/lib/main.dart` — Supabase initialization, FCM, ProviderScope.
- `app/lib/router.dart` — go_router auth/onboarding guards.
- `app/lib/state/providers.dart` — Riverpod app state.
- `app/lib/services/api.dart` — Edge Function REST/SSE client.
- `app/lib/services/notifications.dart` — FCM token registration.
- `app/lib/screens/` — feature screens.
- `app/lib/widgets/tournament_card.dart` — tournament card.
- `app/lib/utils/grade_labels.dart` — grade display labels.

## Environment variables

### Edge Function secrets

```text
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.0-flash
SUPABASE_URL=                 # Supabase injects this
SUPABASE_ANON_KEY=            # Supabase injects this
SUPABASE_SERVICE_ROLE_KEY=    # Supabase injects this
SUPABASE_PUBLISHABLE_KEYS=    # JSON dictionary; userClient uses default first
SUPABASE_SECRET_KEYS=         # JSON dictionary; serviceClient uses default first
FCM_SERVER_KEY=               # optional push sending
CRAWL_TENNIS_GWANGJU_URL=     # optional crawler targets
CRAWL_TENNIS_JEONNAM_URL=
CRAWL_TENNIS_KOREA_URL=
```

### DB GUC for cron → Edge Function invocation

```sql
alter database postgres set app.cron_invoke_url = 'https://<project>.functions.supabase.co';
alter database postgres set app.cron_invoke_key = '<internal-random-cron-secret>';
```

### Flutter `--dart-define`

```text
SUPABASE_URL=
SUPABASE_ANON_KEY=
API_BASE_URL=                 # optional; defaults to $SUPABASE_URL/functions/v1
GOOGLE_WEB_CLIENT_ID=         # optional
GOOGLE_IOS_CLIENT_ID=         # optional
```

## Operational notes

- User submissions start as `tournaments.status='draft'` and become `published` through admin approval.
- Crawler-created tournaments are currently inserted as `published` without manual review.
- Tournament content updates invalidate embeddings by setting `embedding = null`; `embed-pending` recomputes.
- Notification duplicates are prevented by the unique key on `notifications_log(user, tournament, type)`.
- Admin is determined by `users.role='admin'`; RLS uses the `is_admin()` SECURITY DEFINER helper.
- Kakao login is not Supabase standard OAuth; add later with an Edge Function + `signInWithIdToken` pattern.
