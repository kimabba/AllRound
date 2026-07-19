# 2026-07-19 Design & Security Smoke Report

## Scope

- PureForm Sports design contract and global bottom AI entry
- Home, tournaments, tournament detail, clubs, MY, login, and speed-gun preview routes
- 320px / 200% text, dark-mode, and long-Korean layout contracts
- Deterministic loading, empty, offline, permission-denied, slow-chat, and
  sanitized chat-error states
- Cross-account chat, local avatar, push-token, AI-cache, and account-deletion boundaries
- Upload-image metadata removal, Storage ownership/listing, private report evidence,
  and public-media deletion on account removal
- Fresh local Supabase migration replay
- Eight synthetic account personas, pgTAP authorization/privacy suites, and
  Chrome/macOS application E2E
- Eighteen current 390×844 mobile screenshots with exact-name, PNG-integrity,
  dimension, credential, and SHA-256 evidence gates
- Flutter accessibility guidelines for labels, contrast, iOS/Android tap targets,
  chat context state, message reading order, and citation links

Only synthetic local data was used. Production data, real member accounts, real
FCM delivery, and live Gemini calls were not used.

## Result

| Gate | Result | Evidence |
|---|---|---|
| Latest UI static gates | PASS | PureForm literal contract, enum, expanded secret scan, QA shell syntax, diff whitespace |
| Repository harness | PASS | enum, static rules, secret scan, Flutter, Deno |
| Flutter analyze | PASS | no issues |
| Flutter tests | PASS | 245 tests |
| Deno tests | PASS | 205 tests |
| Database security tests | PASS | 100 pgTAP assertions across seven suites |
| Local DB reset | PASS | all migrations replayed from an empty DB |
| Night Shift | PASS | run `20260719T011546Z-33062`, 15/15 steps |
| Chrome application E2E | PASS | eight personas, core journeys, real local entity-chat response, admin boundary |
| macOS application E2E | PASS | seven login, onboarding, tournament, club, MY, and chat journeys; no tap/overflow exception |
| Mobile design evidence hard gate | PASS | exact 18-file set at 390×844, PNG integrity and SHA-256 manifest |
| Storage privacy API | PASS | owner-only listing, private evidence, age gate, public download |
| Account deletion API | PASS | synthetic Auth/public row/media removed; re-login denied |
| Upload metadata | PASS | JPEG EXIF and PNG text stripped; orientation/transparency preserved |
| Push ownership | PASS | one synthetic physical token transferred A to B, then unbound |
| AI cache isolation | PASS | B could not read A cache; A deletion removed cache; retry succeeded |
| Accessibility guidelines | PASS | labels, WCAG text contrast, iOS 44px, Android 48px |
| Visual review | PASS | all 18 current screenshots inspected; no visible clipping, overlap, or mixed visual system |
| iOS simulator E2E | BLOCKED | ffmpeg plugin has no arm64 iOS Simulator slice |

The results above are from the final current-worktree rerun after the responsive
support-screen, chat-authorship, E2E hit-target, and `skeletonizer` compatibility
repairs. Only local Supabase and synthetic accounts were used.

## Design decisions verified

- The global AI entry is the only primary chat entry on Home.
- The dock shows current screen context and sits above the four text tabs.
- Login, onboarding, speed-gun, admin, and full chat do not show the dock.
- Tournament and club entity context is off by default and requires explicit user selection.
- Email signup collects birth date before submission; the Auth hook rejects
  missing, malformed, or under-14 values before creating `auth.users`.
- Google is labeled and explained as existing-account login only. New Google
  identities are rejected by the creation hook and directed to email signup.
- The chat sheet uses one header, flat suggestion rows, a compact growing composer,
  and a disabled send action for empty input.
- Chat and navigation fixed sizes are tokenized at a cross-platform 48px minimum
  and protected by a 320px / 130% text widget test.
- Screen-reader semantics expose one dock action and one context toggle instead
  of duplicate nested controls.
- The four bottom tabs expose their full 64px region to accessibility instead of
  the former 22px text-only hit region.
- AI messages remain visually selectable but are read as one author-plus-content
  unit; only the latest completed AI answer is a live region.
- Citation links expose a named link action with a 48px minimum target.
- Loading, empty, offline, permission-denied, long-Korean, slow-chat, and
  sanitized chat-error states are deterministic widget-test scenarios.
- MY settings, favorite clubs, rules categories, friend schedules, blocked-user
  loading, club introduction/management, and tournament submission now use the
  same flat sections, 20px alignment, token radii, and 48px controls.
- Empty search/notification actions were removed from the friend schedule header;
  its month controls now expose named 48px actions.
- The friend-calendar concept remains covered by a deterministic responsive
  widget test, but its synthetic people and dates are no longer reachable from
  the release router. The 18-screen evidence set now covers real MY appearance
  and account settings instead.
- Club detail tabs scroll from the leading edge, preventing clipping at 320px
  with 130% text.
- The evidence runner now fixes Chrome to a 390×844 viewport and rejects missing,
  renamed, malformed, or incorrectly sized files across 18 required screens.
- The current 18-screen set was visually inspected after the automated gate; its
  spacing, typography, dividers, control radii, and blue global-chat emphasis are
  consistent, with no visible clipping or overlap.
- The 320px / 200% dark-mode pass found and repaired two real overflows: Home
  filter tabs and shared button labels now flex within the available width.
- Full onboarding E2E enters profile fields, birth date, region, and sport grade,
  then verifies the stored profile and personalized Home with the global AI dock.
- Personalized Home now waits for a real matching local result instead of accepting
  a loading skeleton as successful evidence.
- Tournament discovery opens its detail screen, explicit entity context can be
  attached to chat, favorites round-trip through the database, and the restored
  tournament appears again in MY.
- Club E2E proves that an applicant sees pending approval without management,
  while the owner sees the management workspace.
- Owner-club E2E explicitly attaches the public club context, sends a real local
  chat message through the Edge Function, and verifies the deterministic assistant
  response instead of accepting an open sheet as success.
- The current visual evidence set covers Home, tournaments, clubs, tournament
  detail, attached-context chat, MY records/settings, club applicant/management,
  login error, full chat, More, notifications, favorites, rules, blocked users,
  tournament submission, and the completed pre-account age field.

## Objective traceability

| Objective requirement | Local result | Authoritative evidence |
|---|---|---|
| Global bottom chat is the primary entry | PASS | four-tab E2E, sheet/full-chat draft, entity opt-in |
| Pureform is consistent on major journeys | PASS (local) | design contract, 200% tests, 18 inspected current PNGs, exact evidence gate |
| Signup through core usage is automated | PASS | full onboarding, Home, tournament, favorite, MY, club roles |
| Security and privacy boundaries are automated | PASS | 100 pgTAP checks, API smoke, advisors, credential scan |
| Accessibility states are automated | PASS (local) | official four guidelines, 320px/200%, dark, long Korean, states |
| No unapproved repository publication | PASS | no commit, push, PR, merge, deploy, or production mutation |
| Physical-device and staging launch gates | OPEN | listed below; local evidence cannot prove external systems |

## Security changes verified

- Auth identity changes reset in-memory chat messages, conversation ID, and draft.
- Device-local avatar keys are user-scoped; the legacy shared key is deleted.
- Sign-out attempts to unbind every push destination before ending the session.
- One physical push token can belong to only one account in the database.
- AI cache rows have an owner, are queried per owner, cascade on account deletion,
  and expired rows are physically removed by a daily job.
- Account data deletion is idempotent, so a failed Auth deletion can be retried.
- Delete-account failures no longer return internal database/Auth error details.
- Club/member direct update policies cannot be used to self-approve a club or
  promote a member to owner.
- Authenticated users can only change an alert's read state, not its server-owned
  title, body, recipient, delivery state, or references.
- Accounts without a verified 14+ birth date cannot register sports/orgs, submit
  tournaments, create/join clubs, or invoke cost-producing chat through either
  direct SQL or Edge Functions.
- Email signup birth date is validated by a Before User Created Auth Hook and
  copied into the application profile in the same account-creation transaction.
  Missing, malformed, and under-14 HTTP signup attempts create no account.
- User-controlled profile and retrieved fields are kept out of the system prompt,
  placed in one untrusted data block, and cannot forge its delimiter.
- Authenticated app clients can no longer insert or rewrite any chat turn directly;
  only the verified chat Edge Function service writer persists user and assistant turns.
- Explicit sign-out and account deletion await user-scoped local preference cleanup
  before ending the Auth session; the auth listener remains a fallback boundary.
- Credential scanning now includes Supabase secret keys, PEM private keys, and
  service-account JSON markers in both repository and run-artifact gates.
- Onboarding/profile avatar loading captures the user-scoped key before async work,
  avoiding disposed-state access and cross-account key drift.
- Every app image-upload path decodes and re-encodes pixels before persistence,
  removing EXIF, capture location/time, comments, and PNG text metadata.
- New public media uses a random 192-bit object name instead of an account UUID.
- Storage writes and listings authorize against JWT-derived `owner_id`; public
  download does not make the object inventory enumerable by other accounts.
- Report evidence remains in a private bucket and is readable only by its owner
  or an administrator.
- Account deletion removes public Storage objects and their database URLs before
  deleting Auth, while keeping the flow safely retryable after a partial failure.
- Partner/opponent and moderation-audit foreign keys no longer block account
  deletion; retained shared rows lose the deleted account reference.

## Fresh-reset failures found and repaired

The first empty-DB replay exposed existing migration-history defects before the
new security migrations were reached. Each retry stopped at the next distinct
cause; no loop repeated the same failure.

1. An old function signature was hardened after that overload had already been removed.
2. Two migration files shared the same timestamp; one was byte-for-byte duplicated later.
3. Fresh databases were missing the expected club read policy and optional direct-write
   policies were altered even when absent.
4. A stale tennis enum overload blocked enum removal.
5. The new cache RPC required an explicitly schema-qualified pgvector operator.

After those repairs, `supabase db reset` completed successfully.

## Release blockers still open

1. Signup consent and privacy-policy wording do not yet clearly describe the
   profile data sent to the AI provider, actual retention, and deletion behavior.
   Product/legal review is required before store release.
2. Deterministic prompt-boundary tests now cover real chat composition code, but a
   sandboxed real-model red-team evaluation is still required for behavior-level proof.
3. Production Supabase Auth settings—including activation of the new Before User
   Created Hook—deployed RLS parity, real FCM logout delivery, existing-user Google
   OAuth, account deletion, camera/upload, and live SSE failure behavior were not tested.
4. Automated 200% text and dark-mode widget passes now succeed, but physical
   iOS/Android VoiceOver/TalkBack and device text-scaling passes remain required.
   The installed iOS 26.5 simulator cannot build this app because
   `ffmpeg_kit_flutter_new` lacks an arm64 Simulator slice; the dependency or a
   QA build flavor must be changed before simulator E2E can become a hard gate.
5. Private report evidence intentionally survives account deletion for abuse
   investigation, but its exact retention period and automatic expiry job require
   product/legal approval before release.

## Non-blocking tooling warning

- The current complete local build passed, but Flutter reports that `tflite_flutter` and
  `ffmpeg_kit_flutter_new` do not support Swift Package Manager on iOS/macOS.
  Recheck or replace these plugins before a future Flutter upgrade turns the
  warning into a build error.
- A real iPhone 17 Pro simulator preflight reached Xcode and confirmed that
  `ffmpeg_kit_flutter_new` also lacks the arm64 architecture required by Apple
  Silicon iOS 26+ simulators. Generated Xcode changes from that failed preflight
  were removed from the working tree.
- `flutter_markdown 0.7.7+1` is discontinued in favor of
  `flutter_markdown_plus`; migrate it as a separate dependency change with
  rendered-chat regression tests instead of bundling a broad package upgrade.
- `skeletonizer` was upgraded from 1.4.3 to 2.1.3 because the older release did
  not implement the current Flutter Canvas superellipse API on web/macOS.
- Flutter reports 51 newer packages outside current constraints. This is an
  upgrade backlog, not a reason to mass-update release dependencies without
  package-by-package compatibility and security review.

## Next automation slice

1. Apply and verify the Before User Created Hook in staging/production Auth settings.
2. Add the approved report-evidence retention window and automated expiry cleanup.
3. Run staging parity checks for deployed Auth, RLS, FCM, existing-user Google OAuth,
   account deletion,
   camera/upload, and live SSE behavior.
4. Add Patrol-based physical Android/iOS permission and accessibility tests.
5. Replace or isolate the ffmpeg plugin for a simulator-compatible QA flavor,
   then promote iOS E2E after repeated stable passes.
6. Run a sandboxed real-model prompt-injection and unsafe-response evaluation.

The final local report is `artifacts/qa/20260719T011546Z-33062/summary.md`.
Its visual evidence is under `artifacts/qa/20260719T011546Z-33062/screenshots/`.

No commit, push, pull request, deployment, or production mutation was performed.
