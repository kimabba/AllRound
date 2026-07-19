# Harness Rules

Load this when adding tests, CI, scripts, custom checks, or new project rules.

## Definition

A harness is the automated or semi-automated layer that turns project rules into gates.
Documentation alone is not a harness; a rule is stronger when it has a test, script, SQL fixture, or CI job.

## Layered model

1. **Domain harness** — sports/grades/eligibility, published visibility, pagination-after-filtering, notification dedup.
2. **Security/operations harness** — RLS, cron secrets, rate limits, prompt-injection guards, secret scanning.
3. **Code quality harness** — `flutter analyze`, `flutter test`, `deno fmt`, `deno lint`, `deno check`, `deno test`.
4. **Feature harness** — speed-gun fixtures, chat prompt safety tests, crawler parsing fixtures.

## Root-file policy

- Keep `AGENTS.md` and `CLAUDE.md` small.
- New detailed rules go into `docs/rules/*.md`.
- If agents need to discover the new file, add one row to the load-on-demand table in `AGENTS.md`.

## Script shape

```text
scripts/harness/
  run_all.sh              # one local entrypoint for common gates
  check_enums.py          # Dart/TS/SQL enum consistency
  check_static_rules.py   # root rules, docs/templates, Pureform token drift
  check_secrets.sh        # cheap secret scanning for git-visible files
```

## Current merge gates

- Enum consistency across Dart, TypeScript, SQL, and seed data.
- Root agent file length guard to prevent rule bloat.
- Required `docs/rules/` files exist and are linked from `AGENTS.md`.
- GitHub PR/Issue templates and harness workflow exist.
- User UI cannot introduce undocumented radius or fixed button-size literals;
  `AppRadius` and `AppSizes` are the contract.
- Cheap secret scan for files Git would track or add.
- Flutter `analyze` and `test`.
- Deno `fmt`, `lint`, `check`, and `test`.
- Speed-gun basic calculator regression tests.

## Local checks

Use the smallest relevant set during development, or run all common gates:

```bash
scripts/harness/run_all.sh
```

Individual gates:

```bash
python3 scripts/harness/check_enums.py
python3 scripts/harness/check_static_rules.py
bash scripts/harness/check_secrets.sh

cd app && flutter analyze && flutter test

cd supabase/functions
deno fmt --check */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno lint --config deno.json */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno check --config deno.json */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno test --config deno.json --allow-env --allow-read tests
```

## Next harness candidates

- Same-sport tournament eligibility SQL/RPC fixtures.
- Draft tournaments hidden from user search.
- RAG prompt-injection safety tests.
- Speed-gun calibration and speed-range fixtures.
- Crawler parsing fixtures for source markup drift.
- DB reset smoke checks once local Supabase setup is standardized.
