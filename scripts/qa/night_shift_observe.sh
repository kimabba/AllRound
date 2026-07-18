#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
RUN_ID="${QA_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
ARTIFACT_DIR="$ROOT/artifacts/qa/$RUN_ID"
EVENTS_FILE="$ARTIFACT_DIR/events.jsonl"
SUMMARY_FILE="$ARTIFACT_DIR/summary.md"
MANIFEST_FILE="$ARTIFACT_DIR/manifest.json"
TIMEOUT_RUNNER="$ROOT/scripts/qa/run_with_timeout.pl"
LOCK_DIR="${TMPDIR:-/tmp}/allround-night-shift.lock"
MAX_RUNTIME_SECONDS="${QA_MAX_RUNTIME_SECONDS:-3600}"
RUN_STARTED_AT="$(date +%s)"
RESET_LOCAL=true
DATA_PROVENANCE="pending_local_reset"
CONTAINS_REAL_PERSONAL_DATA=null
LOCK_HELD=false
FAILED_STEPS=0

export SUPABASE_BIN

usage() {
  echo "사용법: scripts/qa/night_shift_observe.sh [--reset-local|--reuse-local-unsafe]"
  echo "  기본값/--reset-local     로컬 DB를 reset한 뒤 합성 fixture와 테스트를 실행"
  echo "  --reuse-local-unsafe     기존 로컬 DB를 재사용하며 데이터 출처를 unknown으로 기록"
}

for arg in "$@"; do
  case "$arg" in
    --reset-local) RESET_LOCAL=true ;;
    --reuse-local-unsafe)
      RESET_LOCAL=false
      DATA_PROVENANCE="unknown_reused_local"
      CONTAINS_REAL_PERSONAL_DATA=null
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "알 수 없는 인자: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] ||
  [[ "$RUN_ID" == *..* ]]; then
  echo "QA_RUN_ID는 영문·숫자·점·밑줄·하이픈만 사용할 수 있습니다." >&2
  exit 2
fi
if [[ ! "$MAX_RUNTIME_SECONDS" =~ ^[0-9]+$ ]] ||
  (( MAX_RUNTIME_SECONDS < 60 )); then
  echo "QA_MAX_RUNTIME_SECONDS는 60 이상의 정수여야 합니다." >&2
  exit 2
fi
if [[ -e "$ARTIFACT_DIR" ]]; then
  echo "artifact 디렉터리가 이미 존재합니다: $ARTIFACT_DIR" >&2
  exit 2
fi

mkdir -p "$ARTIFACT_DIR/steps"
cd "$ROOT"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

record_event() {
  local step="$1"
  local status="$2"
  local classification="$3"
  local duration_seconds="$4"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"timestamp":"%s","run_id":"%s","step":"%s","status":"%s","classification":"%s","duration_seconds":%s,"artifact":"steps/%s.log"}\n' \
    "$timestamp" \
    "$(json_escape "$RUN_ID")" \
    "$(json_escape "$step")" \
    "$(json_escape "$status")" \
    "$(json_escape "$classification")" \
    "$duration_seconds" \
    "$(json_escape "$step")" >> "$EVENTS_FILE"
}

run_step() {
  local step="$1"
  local classification="$2"
  local step_timeout="$3"
  shift 3
  local started_at ended_at duration elapsed remaining effective_timeout
  local log_file command_status event_status command_name function_source
  local -a timed_command
  started_at="$(date +%s)"
  log_file="$ARTIFACT_DIR/steps/$step.log"
  elapsed=$((started_at - RUN_STARTED_AT))
  remaining=$((MAX_RUNTIME_SECONDS - elapsed))

  if (( remaining <= 0 )); then
    echo "전체 실행 제한 ${MAX_RUNTIME_SECONDS}초를 초과했습니다." > "$log_file"
    record_event "$step" "timed_out" "$classification" 0
    FAILED_STEPS=$((FAILED_STEPS + 1))
    echo "[$step] 전체 실행 시간 초과" >&2
    return 1
  fi
  if (( step_timeout < remaining )); then
    effective_timeout=$step_timeout
  else
    effective_timeout=$remaining
  fi

  command_name="$1"
  if declare -F "$command_name" >/dev/null; then
    shift
    function_source="$(declare -f "$command_name")"
    timed_command=(
      bash -c "$function_source; $command_name \"\$@\""
      "qa-$command_name"
      "$@"
    )
  else
    timed_command=("$@")
  fi

  echo "[$step] 실행 중..."
  if "$TIMEOUT_RUNNER" "$effective_timeout" "${timed_command[@]}" >"$log_file" 2>&1; then
    ended_at="$(date +%s)"
    duration=$((ended_at - started_at))
    record_event "$step" "passed" "$classification" "$duration"
    echo "[$step] 통과"
    return 0
  else
    command_status=$?
  fi

  ended_at="$(date +%s)"
  duration=$((ended_at - started_at))
  if (( command_status == 124 )); then
    event_status="timed_out"
  else
    event_status="failed"
  fi
  record_event "$step" "$event_status" "$classification" "$duration"
  FAILED_STEPS=$((FAILED_STEPS + 1))
  echo "[$step] $event_status — $log_file 확인" >&2
  return 1
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=true
  else
    local owner_pid=""
    if [[ -f "$LOCK_DIR/owner" ]]; then
      owner_pid="$(awk -F= '$1 == "pid" {print $2}' "$LOCK_DIR/owner")"
    fi
    if [[ "$owner_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
      rm -f "$LOCK_DIR/owner"
      rmdir "$LOCK_DIR" 2>/dev/null || true
      if mkdir "$LOCK_DIR" 2>/dev/null; then
        LOCK_HELD=true
      fi
    fi
  fi

  if ! $LOCK_HELD; then
    echo "다른 Night Shift 실행이 로컬 DB를 사용 중입니다." >&2
    return 1
  fi

  printf 'pid=%s\nrun_id=%s\nstarted_at=%s\n' \
    "$$" "$RUN_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK_DIR/owner"
}

release_lock() {
  if $LOCK_HELD; then
    rm -f "$LOCK_DIR/owner"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=false
  fi
}

start_local_supabase() {
  # supabase start의 stdout에는 로컬 키가 포함될 수 있어 저장하지 않는다.
  "$SUPABASE_BIN" start >/dev/null
}

reset_local_database() {
  "$SUPABASE_BIN" db reset --local
}

seed_personas() {
  local project_id db_container
  project_id="$(awk -F= '$1 ~ /^[[:space:]]*project_id[[:space:]]*$/ {
    gsub(/[[:space:]\"]/, "", $2); print $2
  }' supabase/config.toml)"
  if [[ -z "$project_id" ]]; then
    echo "supabase/config.toml에서 project_id를 찾을 수 없습니다." >&2
    return 1
  fi
  db_container="supabase_db_${project_id}"
  docker exec -i "$db_container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    < supabase/qa/personas.sql
}

run_database_tests() {
  "$SUPABASE_BIN" test db --local supabase/tests/database
}

run_security_advisors() {
  local advisors_json invalid_json error_count unexpected_count

  bash scripts/qa/assert_local_supabase.sh >/dev/null
  advisors_json="$(
    "$SUPABASE_BIN" db advisors \
      --local \
      --type security \
      --level warn \
      --fail-on none \
      --output-format json
  )" || return 1

  invalid_json="$(jq -r 'if type == "array" then "false" else "true" end' <<<"$advisors_json")"
  if [[ "$invalid_json" != "false" ]]; then
    echo "Supabase advisor가 예상하지 못한 JSON 형식을 반환했습니다." >&2
    return 1
  fi

  # 현재 허용하는 항목은 pgvector가 public에 설치됐다는 기존 경고 하나뿐이다.
  # 다른 경고가 추가되면 자동으로 실패시켜 검토 없이 기준선이 넓어지지 않게 한다.
  error_count="$(jq '[.[] | select(.level == "ERROR")] | length' <<<"$advisors_json")"
  unexpected_count="$(
    jq '[.[] | select(
      .level != "WARN" or
      .cache_key != "extension_in_public_vector"
    )] | length' <<<"$advisors_json"
  )"

  jq '.' <<<"$advisors_json"
  echo "보안 advisor 결과: 오류 ${error_count}건, 기준선 밖 경고 ${unexpected_count}건"

  if (( error_count > 0 || unexpected_count > 0 )); then
    return 1
  fi
}

run_flutter_observation_tests() {
  (
    cd app
    flutter test test/config_test.dart test/age_test.dart test/moderation_test.dart
  )
}

write_manifest() {
  local commit_sha branch reset_json
  commit_sha="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  if $RESET_LOCAL; then reset_json=true; else reset_json=false; fi
  printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n  "branch": "%s",\n  "mode": "observe-only",\n  "local_db_reset": %s,\n  "data_provenance": "%s",\n  "contains_real_personal_data": %s\n}\n' \
    "$(json_escape "$RUN_ID")" \
    "$(json_escape "$commit_sha")" \
    "$(json_escape "$branch")" \
    "$reset_json" \
    "$(json_escape "$DATA_PROVENANCE")" \
    "$CONTAINS_REAL_PERSONAL_DATA" > "$MANIFEST_FILE"
}

write_summary() {
  local overall
  if (( FAILED_STEPS == 0 )); then overall="PASS"; else overall="FAIL"; fi
  {
    echo "# AllRound Night Shift — $RUN_ID"
    echo
    echo "- 결과: **$overall**"
    echo "- 모드: observe-only"
    echo "- 실패 단계: $FAILED_STEPS"
    echo "- 운영 DB 접근: 없음"
    echo "- 데이터 출처: $DATA_PROVENANCE"
    if [[ "$CONTAINS_REAL_PERSONAL_DATA" == "false" ]]; then
      echo "- 실제 개인정보 사용: 없음"
    else
      echo "- 실제 개인정보 사용: 확인되지 않음(재사용 로컬 DB)"
    fi
    echo
    echo "## 단계별 결과"
    echo
    if [[ -f "$EVENTS_FILE" ]]; then
      while IFS= read -r line; do
        step="$(sed -n 's/.*\"step\":\"\([^\"]*\)\".*/\1/p' <<<"$line")"
        status="$(sed -n 's/.*\"status\":\"\([^\"]*\)\".*/\1/p' <<<"$line")"
        echo "- $step: $status"
      done < "$EVENTS_FILE"
    fi
    echo
    echo "실패 상세는 steps 디렉터리의 로그를 확인하세요. 로그에는 키와 토큰을 저장하지 않습니다."
  } > "$SUMMARY_FILE"
}

write_manifest
: > "$EVENTS_FILE"

finalize() {
  if [[ ! -f "$SUMMARY_FILE" ]]; then
    write_summary
  fi
  release_lock
}
trap finalize EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! acquire_lock; then
  echo "다른 실행과의 로컬 DB 충돌을 막기 위해 시작하지 않았습니다." \
    > "$ARTIFACT_DIR/steps/concurrent-lock.log"
  record_event "concurrent-lock" "blocked" "environment" 0
  FAILED_STEPS=$((FAILED_STEPS + 1))
  write_summary
  exit 1
fi

if ! run_step "supabase-start" "environment" 300 start_local_supabase; then
  write_summary
  exit 1
fi
if ! run_step "local-only-guard-before" "security_guard" 60 bash scripts/qa/assert_local_supabase.sh; then
  write_summary
  exit 1
fi

if $RESET_LOCAL; then
  if ! run_step "database-reset" "environment" 900 reset_local_database; then
    write_summary
    exit 1
  fi
  if ! run_step "local-only-guard-after" "security_guard" 60 bash scripts/qa/assert_local_supabase.sh; then
    write_summary
    exit 1
  fi
  DATA_PROVENANCE="fresh_local_seed"
  CONTAINS_REAL_PERSONAL_DATA=false
  write_manifest
fi

if ! run_step "persona-seed" "fixture" 120 seed_personas; then
  write_summary
  exit 1
fi

run_step "auth-smoke" "authentication" 120 bash scripts/qa/smoke_auth.sh || true
run_step "privacy-rls" "security_test" 1200 run_database_tests || true
run_step "security-advisors" "security_lint" 300 run_security_advisors || true
run_step "secret-scan" "security_test" 300 bash scripts/harness/check_secrets.sh || true
run_step "flutter-observation" "application_test" 1200 run_flutter_observation_tests || true
run_step "flutter-e2e-web" "application_e2e" 1200 bash scripts/qa/run_flutter_e2e.sh --device chrome || true
if [[ "$(uname -s)" == "Darwin" ]]; then
  run_step "flutter-e2e-macos" "application_e2e" 1200 bash scripts/qa/run_flutter_e2e.sh --device macos || true
fi

write_summary
echo "보고서: $SUMMARY_FILE"

if (( FAILED_STEPS > 0 )); then
  exit 1
fi
