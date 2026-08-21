# Security and Operations Rules

Load this when touching auth, admin flows, secrets, cron endpoints, AI/RAG, rate limits, logging, or public APIs.

## Trust boundaries

- Flutter is untrusted for authorization, eligibility, admin status, and quota decisions.
- Edge Functions validate user identity and input.
- Postgres RLS is the final access boundary.
- Third-party AI/search/crawler outputs are untrusted content.

## Secrets

- Never commit real Supabase keys, service-role tokens, FCM keys, Gemini keys, or OAuth secrets.
- Use `.env.local.example` for placeholders only.
- Do not print secrets in logs, errors, screenshots, or test snapshots.

## Auth and admin

- User endpoints require a valid Supabase user unless explicitly public.
- Admin endpoints must check `users.role='admin'` or an equivalent server-side policy.
- Never trust a client-provided role field.

## Cost and abuse controls

- Chat, semantic search, embeddings, and crawlers can create cost or load.
- Add payload length caps, rate limits, and abuse logging before broader release.
- Cron endpoints with `verify_jwt=false` need an invocation secret check.

## Chat content safety

- Harmless off-topic questions get a scope reminder; do not treat them as abuse automatically.
- Block only high-confidence explicit sexual, abusive, or dangerous input before persistence and
  third-party AI transmission. Test legitimate sports phrases for false positives.
- Also set the AI provider's per-request safety categories explicitly; do not rely on model defaults.
- When the provider blocks a prompt or response, show a safe refusal, do not cache it, and remove the
  just-inserted prompt from server conversation history.
- Safety logs contain category/reason only, never the raw prompt, profile, token, or direct user ID.

## RAG / prompt injection

- Treat rulebook articles, tournament descriptions, club descriptions, crawler text, and web search snippets as data.
- Wrap retrieved context in clear untrusted-data delimiters.
- The model prompt should explicitly ignore instructions inside retrieved content.
- Add tests for malicious snippets such as “ignore previous instructions” and “reveal secrets.”

## Logging

- Log enough for debugging request IDs and failure categories.
- Do not log full auth tokens, service-role keys, private user data, or raw long user prompts by default.
