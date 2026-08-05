# Coding Rules

Load this when writing or reviewing code, migrations, tests, scripts, or CI.

## TypeScript / Deno Edge Functions

- `any` is prohibited.
- Function arguments, return values, variables, and object fields should have explicit types when inference is not obvious.
- External API responses and `JSON.parse`/`req.json()` results should enter as `unknown` and be narrowed with type guards or validation functions.
- Type assertions (`as`) are a last resort. Prefer union types, discriminated unions, and `is` predicates.
- Generics must carry real meaning; do not use them to dodge typing.
- `deno check` must pass with zero errors.

## Dart / Flutter

- Avoid `dynamic`. JSON decode boundaries may use `Map<String, dynamic>`, but convert immediately to typed models.
- Nullable fields must be explicit with `?`.
- Avoid forced unwrap (`!`) unless the value was validated directly above or by a clear invariant.
- `flutter analyze` should pass with no warnings or errors.

## SQL migrations

- Every column needs an explicit type.
- Prefer `text` over `varchar` unless there is a clear DB-level reason.
- Reusable enums should use `create type`.
- Every new table must enable RLS and define policies in the same migration.
- Prefer RPC for server-truth domain rules that must not be bypassed by the client.

## Git / PR discipline

- Small commits: one commit = one reason to change.
- Korean commit messages are fine.
- Keep the header around 50 characters when practical.
- Explain “why” and “what” in the body for non-trivial changes.
- **PR and issue text is mirrored to Discord and read by non-developers.** Write it in plain Korean:
  lead with 무엇이 달라지나 / 왜 했나 / 확인하는 법, gloss any jargon once, and push file names,
  function names, and SQL down to a “기술 메모” section at the bottom.
  Full rule (정본): `docs/team/START-HERE.md` → “5-2. PR·이슈는 쉬운 한글로 쓴다”.
  This applies to PRs and issues only — commit messages are unaffected.

## Baseline checks

```bash
cd app && flutter analyze && flutter test
cd supabase/functions && deno fmt --check */index.ts _shared/*.ts && deno lint --config deno.json */index.ts _shared/*.ts && deno check --config deno.json */index.ts _shared/*.ts
```
