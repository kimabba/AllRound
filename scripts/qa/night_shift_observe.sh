#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
RUN_ID="${QA_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
ARTIFACT_DIR="$ROOT/artifacts/qa/$RUN_ID"
EVENTS_FILE="$ARTIFACT_DIR/events.jsonl"
SUMMARY_FILE="$ARTIFACT_DIR/summary.md"
MANIFEST_FILE="$ARTIFACT_DIR/manifest.json"
ARTIFACT_SCAN_STATUS_FILE="$ARTIFACT_DIR/artifact-scan.status"
TIMEOUT_RUNNER="$ROOT/scripts/qa/run_with_timeout.pl"
LOCK_DIR="${TMPDIR:-/tmp}/allround-night-shift.lock"
MAX_RUNTIME_SECONDS="${QA_MAX_RUNTIME_SECONDS:-3600}"
RUN_STARTED_AT="$(date +%s)"
RESET_REQUESTED=true
RESET_COMPLETED=false
DATA_PROVENANCE="pending_local_reset"
CONTAINS_REAL_PERSONAL_DATA=null
LOCK_HELD=false
FAILED_STEPS=0
RUN_INTERRUPTED=false
FINALIZING=false
FAILURE_STATE_UPDATED=false
FAILURE_FINGERPRINT=""
FAILURE_REPEAT_COUNT=0
FAILURE_STATE_FILE="$ROOT/artifacts/qa/failure-state.json"

export SUPABASE_BIN

usage() {
  echo "사용법: scripts/qa/night_shift_observe.sh [--reset-local|--reuse-local-unsafe]"
  echo "  기본값/--reset-local     로컬 DB를 reset한 뒤 합성 fixture와 테스트를 실행"
  echo "  --reuse-local-unsafe     기존 로컬 DB를 재사용하며 데이터 출처를 unknown으로 기록"
}

for arg in "$@"; do
  case "$arg" in
    --reset-local) RESET_REQUESTED=true ;;
    --reuse-local-unsafe)
      RESET_REQUESTED=false
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
    FAILED_STEPS=$((FAILED_STEPS + 1))
    if ! echo "전체 실행 제한 ${MAX_RUNTIME_SECONDS}초를 초과했습니다." > "$log_file"; then
      echo "[$step] 시간 초과 로그를 저장하지 못했습니다." >&2
    fi
    if ! record_event "$step" "timed_out" "$classification" 0; then
      echo "[$step] 시간 초과 event를 저장하지 못했습니다." >&2
    fi
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
    if ! record_event "$step" "passed" "$classification" "$duration"; then
      FAILED_STEPS=$((FAILED_STEPS + 1))
      echo "[$step] 통과 event를 저장하지 못해 실패 처리합니다." >&2
      return 1
    fi
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
  FAILED_STEPS=$((FAILED_STEPS + 1))
  if ! record_event "$step" "$event_status" "$classification" "$duration"; then
    echo "[$step] 실패 event를 저장하지 못했습니다." >&2
  fi
  echo "[$step] $event_status — $log_file 확인" >&2
  return 1
}

process_start_for_pid() {
  local pid="$1"
  ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

lock_is_stale() {
  local owner_file="$LOCK_DIR/owner"
  local owner_pid owner_started_epoch owner_process_start
  local current_process_start owner_command

  [[ -f "$owner_file" ]] || return 0
  owner_pid="$(awk -F= '$1 == "pid" {print $2}' "$owner_file" 2>/dev/null || true)"
  owner_started_epoch="$(awk -F= '$1 == "started_epoch" {print $2}' "$owner_file" 2>/dev/null || true)"
  owner_process_start="$(awk -F= '$1 == "process_start" {sub(/^[^=]*=/, ""); print}' "$owner_file" 2>/dev/null || true)"

  [[ "$owner_pid" =~ ^[0-9]+$ ]] || return 0
  [[ "$owner_started_epoch" =~ ^[0-9]+$ ]] || return 0
  [[ -n "$owner_process_start" ]] || return 0
  kill -0 "$owner_pid" 2>/dev/null || return 0

  if [[ "$owner_process_start" != "unavailable" ]]; then
    current_process_start="$(process_start_for_pid "$owner_pid" || true)"
    if [[ -n "$current_process_start" ]]; then
      [[ "$current_process_start" == "$owner_process_start" ]] || return 0
    fi
  fi
  owner_command="$(ps -p "$owner_pid" -o command= 2>/dev/null || true)"
  if [[ -n "$owner_command" ]]; then
    [[ "$owner_command" == *"night_shift_observe.sh"* ]] || return 0
  fi

  # PID가 살아 있고 확인 가능한 identity도 일치하면 실행 시간만으로 잠금을
  # 탈취하지 않는다. suspend/finalize 지연 중 로컬 DB reset이 겹치는 편이 더 위험하다.
  return 1
}

remove_stale_lock() {
  rm -f "$LOCK_DIR/owner" || return 1
  rmdir "$LOCK_DIR" 2>/dev/null || return 1
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=true
  else
    if lock_is_stale && remove_stale_lock; then
      if mkdir "$LOCK_DIR" 2>/dev/null; then
        LOCK_HELD=true
      fi
    fi
  fi

  if ! $LOCK_HELD; then
    echo "다른 Night Shift 실행이 로컬 DB를 사용 중입니다." >&2
    return 1
  fi

  local process_start
  process_start="$(process_start_for_pid "$$" || true)"
  if [[ -z "$process_start" ]]; then
    process_start="unavailable"
  fi
  if ! printf 'pid=%s\nrun_id=%s\nstarted_at=%s\nstarted_epoch=%s\nprocess_start=%s\n' \
      "$$" \
      "$RUN_ID" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$RUN_STARTED_AT" \
      "$process_start" > "$LOCK_DIR/owner"; then
    echo "Night Shift 잠금 소유자 정보를 저장하지 못했습니다." >&2
    remove_stale_lock || true
    LOCK_HELD=false
    return 1
  fi
}

release_lock() {
  if $LOCK_HELD; then
    rm -f "$LOCK_DIR/owner" || return 1
    rmdir "$LOCK_DIR" 2>/dev/null || return 1
    LOCK_HELD=false
  fi
  return 0
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

run_artifact_credential_scan() {
  local steps_dir="$1"
  local repo_root="$2"
  local status_file="$3"
  local matches=""
  local remaining=""
  local scan_exit=0
  local pattern
  pattern="QaLocal-Only-2026!|(SUPABASE_(ANON|SERVICE_ROLE)_KEY|ANON_KEY|SERVICE_ROLE_KEY)[[:space:]]*[=:][[:space:]]*[\"']?[^[:space:]\"',;]+[\"']?|sb_(publishable|secret)_[A-Za-z0-9_-]{16,}|\"(access_token|refresh_token)\"[[:space:]]*:|eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{10,}|(ws|http)://(127\\.0\\.0\\.1|localhost):[0-9]+/[A-Za-z0-9_?&=./-]{8,}"

  [[ -d "$steps_dir" ]] || {
    echo "단계 로그 디렉터리가 없습니다: $steps_dir" >&2
    printf 'failed\n' > "$status_file" || true
    return 1
  }
  if ! command -v rg >/dev/null 2>&1 || ! command -v perl >/dev/null 2>&1; then
    echo "artifact 검사에 필요한 rg 또는 perl이 없습니다." >&2
    printf 'failed\n' > "$status_file" || true
    return 1
  fi

  matches="$(rg -l --hidden -e "$pattern" "$steps_dir" 2>/dev/null)"
  scan_exit=$?
  if (( scan_exit > 1 )); then
    echo "artifact 파일을 검사하지 못했습니다." >&2
    printf 'failed\n' > "$status_file" || true
    return 1
  fi
  if [[ -n "$matches" ]]; then
    echo "artifact의 민감 패턴을 자동 마스킹하고 실행을 실패 처리합니다:" >&2
    while IFS= read -r matched_file; do
      printf '  - %s\n' "${matched_file#"$repo_root/"}" >&2
      if ! perl -0pi -e '
        s/QaLocal-Only-2026!/<redacted-local-qa-password>/g;
        s/(?:SUPABASE_(?:ANON|SERVICE_ROLE)_KEY|ANON_KEY|SERVICE_ROLE_KEY)\s*[=:]\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s,;]+)/<redacted-supabase-key>/gi;
        s/sb_(?:publishable|secret)_[A-Za-z0-9_-]{16,}/<redacted-supabase-key>/gi;
        s/("(?:access_token|refresh_token)"\s*:\s*")[^"]*"/${1}<redacted>"/gi;
        s/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}/<redacted-jwt>/g;
        s{(?:ws|http)://(?:127\.0\.0\.1|localhost):[0-9]+/[A-Za-z0-9_?&=./-]{8,}}{<redacted-local-debug-uri>}g;
      ' "$matched_file"; then
        printf 'failed\n' > "$status_file" || true
        return 1
      fi
    done <<< "$matches"

    remaining="$(rg -l --hidden -e "$pattern" "$steps_dir" 2>/dev/null)"
    scan_exit=$?
    if (( scan_exit > 1 )); then
      echo "마스킹 후 artifact를 재검사하지 못했습니다." >&2
      printf 'failed\n' > "$status_file" || true
      return 1
    fi
    if [[ -n "$remaining" ]]; then
      echo "artifact 민감 패턴을 완전히 마스킹하지 못했습니다." >&2
      printf 'failed\n' > "$status_file" || true
      return 1
    fi
    printf 'redacted\n' > "$status_file" || return 1
    return 1
  fi
  printf 'clean\n' > "$status_file" || return 1
  echo "artifact credential 패턴 검사 통과"
}

write_manifest() {
  local commit_sha branch requested_json completed_json
  commit_sha="$(git rev-parse HEAD)" || return 1
  branch="$(git branch --show-current)" || return 1
  if $RESET_REQUESTED; then requested_json=true; else requested_json=false; fi
  if $RESET_COMPLETED; then completed_json=true; else completed_json=false; fi
  printf '{\n  "run_id": "%s",\n  "commit_sha": "%s",\n  "branch": "%s",\n  "mode": "observe-only",\n  "reset_requested": %s,\n  "reset_completed": %s,\n  "data_provenance": "%s",\n  "contains_real_personal_data": %s\n}\n' \
    "$(json_escape "$RUN_ID")" \
    "$(json_escape "$commit_sha")" \
    "$(json_escape "$branch")" \
    "$requested_json" \
    "$completed_json" \
    "$(json_escape "$DATA_PROVENANCE")" \
    "$CONTAINS_REAL_PERSONAL_DATA" > "$MANIFEST_FILE"
}

update_failure_state() {
  local failure_event failure_step failure_status failure_classification
  local previous_fingerprint="" previous_count=0 state_tmp

  if (( FAILED_STEPS == 0 )); then
    FAILURE_FINGERPRINT=""
    FAILURE_REPEAT_COUNT=0
  else
    failure_event="$(jq -cs '[.[] | select(.status != "passed")][0] // empty' "$EVENTS_FILE")" || return 1
    if [[ -z "$failure_event" ]]; then
      failure_event='{"step":"unrecorded-runner-failure","status":"failed","classification":"runner"}'
    fi
    failure_step="$(jq -r '.step // "unrecorded"' <<< "$failure_event")" || return 1
    failure_status="$(jq -r '.status // "failed"' <<< "$failure_event")" || return 1
    failure_classification="$(jq -r '.classification // "runner"' <<< "$failure_event")" || return 1
    FAILURE_FINGERPRINT="$(
      printf '%s|%s|%s' "$failure_step" "$failure_status" "$failure_classification" \
        | shasum -a 256 \
        | awk '{print $1}'
    )" || return 1

    if [[ -f "$FAILURE_STATE_FILE" ]] && jq -e 'type == "object"' "$FAILURE_STATE_FILE" >/dev/null 2>&1; then
      previous_fingerprint="$(jq -r '.fingerprint // ""' "$FAILURE_STATE_FILE")" || return 1
      previous_count="$(jq -r '.repeat_count // 0' "$FAILURE_STATE_FILE")" || return 1
      [[ "$previous_count" =~ ^[0-9]+$ ]] || previous_count=0
    fi
    if [[ "$FAILURE_FINGERPRINT" == "$previous_fingerprint" ]]; then
      FAILURE_REPEAT_COUNT=$((previous_count + 1))
    else
      FAILURE_REPEAT_COUNT=1
    fi
  fi

  state_tmp="$(mktemp "$ROOT/artifacts/qa/.failure-state.XXXXXX")" || return 1
  if ! jq -n \
    --arg fingerprint "$FAILURE_FINGERPRINT" \
    --argjson repeat_count "$FAILURE_REPEAT_COUNT" \
    --arg run_id "$RUN_ID" \
    --arg summary "artifacts/qa/$RUN_ID/summary.md" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      fingerprint: (if $fingerprint == "" then null else $fingerprint end),
      repeat_count: $repeat_count,
      run_id: $run_id,
      summary: $summary,
      updated_at: $updated_at
    }' > "$state_tmp"; then
    rm -f "$state_tmp"
    return 1
  fi
  if ! mv "$state_tmp" "$FAILURE_STATE_FILE"; then
    rm -f "$state_tmp"
    return 1
  fi
  FAILURE_STATE_UPDATED=true
}

write_summary() {
  local overall step status artifact_scan_status
  artifact_scan_status="$(sed -n '1p' "$ARTIFACT_SCAN_STATUS_FILE" 2>/dev/null || true)"
  if (( FAILED_STEPS == 0 )); then overall="PASS"; else overall="FAIL"; fi
  {
    echo "# AllRound Night Shift — $RUN_ID"
    echo
    echo "- 결과: **$overall**"
    echo "- 모드: observe-only"
    echo "- 실패 단계: $FAILED_STEPS"
    echo "- 동일 실패 반복: ${FAILURE_REPEAT_COUNT}회"
    if [[ -n "$FAILURE_FINGERPRINT" ]]; then
      echo "- 실패 fingerprint: \`$FAILURE_FINGERPRINT\`"
    fi
    echo "- 운영 DB 접근: 없음"
    echo "- 로컬 DB reset 요청: $RESET_REQUESTED"
    echo "- 로컬 DB reset 완료: $RESET_COMPLETED"
    echo "- 데이터 출처: $DATA_PROVENANCE"
    if [[ "$CONTAINS_REAL_PERSONAL_DATA" == "false" ]]; then
      echo "- 실제 개인정보 사용: 없음"
    elif [[ "$DATA_PROVENANCE" == "pending_local_reset" ]]; then
      echo "- 실제 개인정보 사용: 로컬 데이터 사용 전 중단"
    else
      echo "- 실제 개인정보 사용: 확인되지 않음(재사용 로컬 DB)"
    fi
    case "$artifact_scan_status" in
      clean) echo "- artifact 민감정보 검사: 통과" ;;
      redacted) echo "- artifact 민감정보 검사: 패턴 발견 후 자동 마스킹(실행 실패)" ;;
      *) echo "- artifact 민감정보 검사: 확인 실패" ;;
    esac
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
    echo "실패 상세는 steps 디렉터리의 로그를 확인하세요. 민감 패턴 발견 시 원문은 자동 마스킹되고 실행은 실패합니다."
  } > "$SUMMARY_FILE"
}

ensure_artifact_safety() {
  local scan_log="$ARTIFACT_DIR/steps/artifact-credential-scan.log"
  local scan_status="failed"

  if run_artifact_credential_scan \
    "$ARTIFACT_DIR/steps" \
    "$ROOT" \
    "$ARTIFACT_SCAN_STATUS_FILE" > "$scan_log" 2>&1; then
    scan_status="clean"
  else
    scan_status="$(sed -n '1p' "$ARTIFACT_SCAN_STATUS_FILE" 2>/dev/null || true)"
    [[ -n "$scan_status" ]] || scan_status="failed"
  fi

  if [[ "$scan_status" == "clean" ]]; then
    if ! record_event "artifact-credential-scan" "passed" "security_test" 0; then
      FAILED_STEPS=$((FAILED_STEPS + 1))
      echo "artifact 검사 event를 저장하지 못했습니다." >&2
      return 1
    fi
    return 0
  fi

  FAILED_STEPS=$((FAILED_STEPS + 1))
  record_event "artifact-credential-scan" "failed" "security_test" 0 || true
  echo "artifact 민감정보 검사 실패 — $scan_log 확인" >&2
  return 1
}

finalize() {
  local exit_status=$?
  if $FINALIZING; then
    return
  fi
  FINALIZING=true
  trap - EXIT INT TERM

  if (( exit_status != 0 && FAILED_STEPS == 0 )); then
    FAILED_STEPS=$((FAILED_STEPS + 1))
  fi
  if ! release_lock; then
    FAILED_STEPS=$((FAILED_STEPS + 1))
    exit_status=1
    if ! printf 'Night Shift 잠금을 해제하지 못했습니다: %s\n' "$LOCK_DIR" \
      > "$ARTIFACT_DIR/steps/lock-release.log"; then
      echo "잠금 해제 실패 로그를 저장하지 못했습니다." >&2
    fi
    record_event "lock-release" "failed" "runner" 0 || true
    echo "Night Shift 잠금을 해제하지 못했습니다: $LOCK_DIR" >&2
  fi
  if ! ensure_artifact_safety; then
    exit_status=1
  fi
  if ! $FAILURE_STATE_UPDATED && ! update_failure_state; then
    FAILED_STEPS=$((FAILED_STEPS + 1))
    exit_status=1
    echo "반복 실패 상태를 저장하지 못했습니다." >&2
  fi
  if ! write_summary; then
    exit_status=1
    echo "Night Shift summary를 저장하지 못했습니다." >&2
  fi
  if (( FAILED_STEPS > 0 && exit_status == 0 )); then
    exit_status=1
  fi
  echo "보고서: $SUMMARY_FILE"
  exit "$exit_status"
}

handle_signal() {
  local signal_name="$1"
  local exit_code="$2"
  RUN_INTERRUPTED=true
  FAILED_STEPS=$((FAILED_STEPS + 1))
  if ! printf 'Night Shift가 %s 신호로 중단되었습니다.\n' "$signal_name" \
    > "$ARTIFACT_DIR/steps/interrupted.log"; then
    echo "중단 로그를 저장하지 못했습니다." >&2
  fi
  record_event "interrupted" "interrupted" "runner" 0 || true
  exit "$exit_code"
}

trap finalize EXIT
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

if ! write_manifest; then
  FAILED_STEPS=$((FAILED_STEPS + 1))
  echo "Night Shift manifest를 생성하지 못했습니다." >&2
  exit 1
fi
if ! : > "$EVENTS_FILE"; then
  FAILED_STEPS=$((FAILED_STEPS + 1))
  echo "Night Shift event 파일을 생성하지 못했습니다." >&2
  exit 1
fi

if ! acquire_lock; then
  FAILED_STEPS=$((FAILED_STEPS + 1))
  if ! echo "다른 실행과의 로컬 DB 충돌을 막기 위해 시작하지 않았습니다." \
    > "$ARTIFACT_DIR/steps/concurrent-lock.log"; then
    echo "동시 실행 차단 로그를 저장하지 못했습니다." >&2
  fi
  record_event "concurrent-lock" "blocked" "environment" 0 || true
  exit 1
fi

if ! run_step "supabase-start" "environment" 300 start_local_supabase; then
  exit 1
fi
if ! run_step "local-only-guard-before" "security_guard" 60 bash scripts/qa/assert_local_supabase.sh; then
  exit 1
fi

if $RESET_REQUESTED; then
  if ! run_step "database-reset" "environment" 900 reset_local_database; then
    exit 1
  fi
  if ! run_step "local-only-guard-after" "security_guard" 60 bash scripts/qa/assert_local_supabase.sh; then
    exit 1
  fi
  RESET_COMPLETED=true
  DATA_PROVENANCE="fresh_local_seed"
  CONTAINS_REAL_PERSONAL_DATA=false
  if ! write_manifest; then
    FAILED_STEPS=$((FAILED_STEPS + 1))
    echo "reset 완료 상태를 manifest에 저장하지 못했습니다." >&2
    exit 1
  fi
fi

if ! run_step "persona-seed" "fixture" 120 seed_personas; then
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

if (( FAILED_STEPS > 0 )); then
  exit 1
fi
