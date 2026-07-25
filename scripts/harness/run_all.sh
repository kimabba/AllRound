#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "== Match-up harness =="

cd "$ROOT"
printf '\n'; echo "[1/7] enum consistency"
python3 scripts/harness/check_enums.py

# 등급 정본↔폴백 대조는 적용된 DB 를 읽는다(JY-321). DB 가 있으면 로컬에서도 태우고,
# 없으면 건너뛰되 조용히 통과하지 않는다 — 실제 강제는 CI database 잡(required)이 한다.
printf '\n'; echo "[2/7] grades parity (DB 정본 대조)"
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
if psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  DATABASE_URL="$DB_URL" python3 scripts/harness/check_grades_parity.py
else
  echo "⚠️  로컬 DB 미접속 — grades parity 건너뜀(supabase start 후 재실행하거나 CI 가 강제)" >&2
fi

printf '\n'; echo "[3/7] static repository rules"
python3 scripts/harness/check_static_rules.py

printf '\n'; echo "[4/7] ranking-rules data (배점표 드리프트)"
python3 scripts/qa/verify_ranking_rules.py

printf '\n'; echo "[5/7] secret scan"
bash scripts/harness/check_secrets.sh

printf '\n'; echo "[6/7] Flutter analyze/test"
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

printf '\n'; echo "[7/7] Deno Edge Function checks"
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
