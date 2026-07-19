#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "== Match-up harness =="

cd "$ROOT"
printf '\n'; echo "[1/5] enum consistency"
python3 scripts/harness/check_enums.py

printf '\n'; echo "[2/5] static repository rules"
python3 scripts/harness/check_static_rules.py

printf '\n'; echo "[3/5] secret scan"
bash scripts/harness/check_secrets.sh

printf '\n'; echo "[4/5] Flutter analyze/test"
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found" >&2
  exit 1
fi
(
  cd "$ROOT/app"
  flutter pub get
  flutter analyze
  flutter test
)

printf '\n'; echo "[5/5] Deno Edge Function checks"
if ! command -v deno >/dev/null 2>&1; then
  echo "deno not found" >&2
  exit 1
fi
(
  cd "$ROOT/supabase/functions"
  deno fmt --check */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
  deno lint --config deno.json */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
  deno check --config deno.json */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
  deno test --config deno.json --allow-env --allow-read tests
)

printf '\n'; echo "✅ Match-up harness passed"
