# Frontend Rules

Load this when touching `app/`, Flutter screens, routing, Riverpod state, API client code, or UX behavior.

## Stack and conventions

- Flutter/Dart app for iOS, Android, and web.
- Riverpod manages app state.
- go_router manages navigation and auth/onboarding guards.
- Supabase client handles auth and calls Edge Functions.
- Follow `CODING_RULES.md` for Dart typing and analyzer rules.

## Source of truth

- The client may improve UX with local filtering, labels, and optimistic state.
- The client must not be the final authority for auth, admin, eligibility, tournament visibility, or rate limits.
- Treat server responses as typed payloads; parse into models before use.

## Important files

- `app/lib/main.dart` — bootstrapping.
- `app/lib/router.dart` — route and auth/onboarding guards.
- `app/lib/state/providers.dart` — shared state.
- `app/lib/services/api.dart` — REST/SSE client.
- `app/lib/services/notifications.dart` — FCM token handling.
- `app/lib/utils/grade_labels.dart` — grade display labels.
- `app/lib/screens/` — feature screens.

## UI/UX rules

- 사용자 UI를 만들거나 수정하기 전에 현재 디자인 기준인
  [`docs/design/pureform-sports-system.md`](../design/pureform-sports-system.md)를 읽고
  색·타이포·간격·공통 컴포넌트·상태·검증 규칙을 따른다.
- Keep grade and sport labels consistent with `DOMAIN_RULES.md`.
- Expose loading, empty, error, and retry states for network screens.
- User-facing errors should be actionable; do not show only raw exceptions.
- Web-specific behavior should be isolated with clear platform branches.

## Checks

```bash
cd app
flutter analyze
flutter test
```
