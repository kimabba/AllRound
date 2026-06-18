# Domain Rules

Load this when touching tournaments, sports, grades, clubs, favorites, notifications, or eligibility logic.

## Sports and grades

| Sport | Grade enum | Display |
|---|---|---|
| tennis | `rookie`, `div5`, `div4`, `div3`, `div2`, `div1` | 신입, 5부, 4부, 3부, 2부, 1부 |
| futsal | `intro`, `beginner`, `intermediate`, `advanced`, `elite` | 입문, 초급, 중급, 고급, 선출 |

Rules:

- One user may register both sports through `user_sports`.
- A tournament is eligible only when the user's grade for the **same sport** is included in `tournaments.eligible_grades`.
- Do not implement eligibility by a plain grade-array overlap without also checking sport; that can create cross-sport false positives.
- Client-side filtering is display-only. Server/DB logic is the final truth.

## Tournament visibility

- Public/user search should expose only `published` tournaments unless the endpoint is explicitly admin-only.
- User submissions start as `draft`.
- Admin approval changes visibility to `published`; rejection should remain non-public.
- Crawler-created tournaments currently publish immediately. If review is introduced, update crawler tests and operational notes.

## Search and filtering

- Pagination should happen **after** all filters that affect result membership.
- `sport`, `grade`, `region_code`, `host_orgs`, status, and text search should be handled server-side when possible.
- Avoid Edge Function post-filtering that can return under-filled pages or inconsistent totals; if temporary, document it as such.
- Prefer an RPC such as `tournaments_for_user_v2` for eligibility + search filters.

## Favorites and notifications

- Favorites are user-scoped.
- Notification duplicate prevention relies on unique `(user, tournament, type)` semantics.
- D-3 and deadline reminders should respect tournament status and user eligibility.

## Domain harness targets

- Enum consistency across SQL, TypeScript, and Dart.
- Same-sport eligibility fixtures.
- Draft tournaments hidden from user search.
- Pagination after filters.
- Notification dedup fixtures.
