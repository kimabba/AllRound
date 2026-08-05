#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "== Match-up harness =="

cd "$ROOT"
printf '\n'; echo "[1/10] enum consistency"
python3 scripts/harness/check_enums.py

# 등급 정본↔폴백 대조는 적용된 DB 를 읽는다(JY-321). DB 가 있으면 로컬에서도 태우고,
# 없으면 건너뛰되 조용히 통과하지 않는다 — 실제 강제는 CI database 잡(required)이 한다.
printf '\n'; echo "[2/10] grades parity (DB 정본 대조)"
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
if psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  DATABASE_URL="$DB_URL" python3 scripts/harness/check_grades_parity.py
else
  echo "⚠️  로컬 DB 미접속 — grades parity 건너뜀(supabase start 후 재실행하거나 CI 가 강제)" >&2
fi

# 협회 정본↔폴백 대조도 같은 이유로 DB 를 직접 읽는다(#330 3번, JY-135 후 공백).
printf '\n'; echo "[3/10] org parity (DB 정본 대조)"
if psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  DATABASE_URL="$DB_URL" python3 scripts/harness/check_org_parity.py
else
  echo "⚠️  로컬 DB 미접속 — org parity 건너뜀(supabase start 후 재실행하거나 CI 가 강제)" >&2
fi

# 부서 정본↔폴백 대조. 랭킹 등급/대회 종목 분류(is_ranking_grade)가 마이그레이션과 앱
# 폴백 사이에서 갈라지는 걸 막는다 — 협회·등급과 같은 스냅샷 다리다.
printf '\n'; echo "[4/10] division parity (DB 정본 대조)"
if psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  DATABASE_URL="$DB_URL" python3 scripts/harness/check_division_parity.py
else
  echo "⚠️  로컬 DB 미접속 — division parity 건너뜀(supabase start 후 재실행하거나 CI 가 강제)" >&2
fi

# pgTAP 은 CI 에만 있어서 로컬 harness 가 초록불이어도 DB 제약·트리거 회귀를 놓쳤다
# (JY-135: 새 트리거가 QA 페르소나 시드를 막는 걸 CI 에서야 발견). 같은 조건부로 태운다.
printf '\n'; echo "[5/10] database pgTAP"
if psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  DB_URL="$DB_URL" bash scripts/qa/run_db_tests.sh
else
  echo "⚠️  로컬 DB 미접속 — pgTAP 건너뜀(supabase start 후 재실행하거나 CI 가 강제)" >&2
fi

printf '\n'; echo "[6/10] static repository rules"
python3 scripts/harness/check_static_rules.py
python3 scripts/harness/check_dependencies.py

printf '\n'; echo "[7/10] ranking-rules data (배점표 드리프트)"
python3 scripts/qa/verify_ranking_rules.py

printf '\n'; echo "[8/10] secret scan"
bash scripts/harness/check_secrets.sh

printf '\n'; echo "[9/10] Flutter analyze/test"
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

printf '\n'; echo "[10/10] Deno Edge Function checks"
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
