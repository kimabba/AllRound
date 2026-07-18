#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_BIN="${SUPABASE_BIN:-supabase}"
DEVICE="chrome"
DRIVER_PID=""
DRIVER_LOG=""

usage() {
  echo "사용법: scripts/qa/run_flutter_e2e.sh [--device <flutter-device-id>]"
}

while (( $# > 0 )); do
  case "$1" in
    --device)
      if (( $# < 2 )); then
        usage >&2
        exit 2
      fi
      DEVICE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "알 수 없는 인자: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT"
bash scripts/qa/assert_local_supabase.sh >/dev/null

# status에는 로컬 키가 포함되므로 출력하지 않고, 권한 600 임시 파일로만 전달한다.
status_env="$($SUPABASE_BIN status -o env 2>/dev/null)"
api_url="$(awk -F= '$1 == "API_URL" {gsub(/^"|"$/, "", $2); print $2}' <<<"$status_env")"
anon_key="$(awk -F= '$1 == "ANON_KEY" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print}' <<<"$status_env")"
unset status_env

runtime_config="$(mktemp "${TMPDIR:-/tmp}/allround-flutter-e2e.XXXXXX")"
cleanup() {
  if [[ -n "$DRIVER_PID" ]] && kill -0 "$DRIVER_PID" 2>/dev/null; then
    kill "$DRIVER_PID" 2>/dev/null || true
    wait "$DRIVER_PID" 2>/dev/null || true
  fi
  rm -f "$runtime_config"
  if [[ -n "$DRIVER_LOG" ]]; then
    rm -f "$DRIVER_LOG"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
chmod 600 "$runtime_config"

jq -n \
  --arg supabase_url "$api_url" \
  --arg anon_key "$anon_key" \
  --arg api_base_url "$api_url/functions/v1" \
  '{
    SUPABASE_URL: $supabase_url,
    SUPABASE_ANON_KEY: $anon_key,
    API_BASE_URL: $api_base_url
  }' > "$runtime_config"

unset anon_key

if [[ "$DEVICE" == "chrome" ]]; then
  chromedriver_bin="${CHROMEDRIVER_BIN:-}"
  if [[ -z "$chromedriver_bin" ]]; then
    chrome_version="$(
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --version \
        | awk '{print $3}'
    )"
    chrome_major="${chrome_version%%.*}"
    chromedriver_bin="$(
      rg --files "$ROOT/chromedriver" 2>/dev/null \
        | rg "/mac[^/]*-${chrome_major}\.[^/]*/.*/chromedriver$" \
        | sort \
        | tail -n 1
    )"
  fi

  if [[ -z "$chromedriver_bin" || ! -x "$chromedriver_bin" ]]; then
    echo "Chrome과 같은 major 버전의 ChromeDriver가 필요합니다." >&2
    echo "설치: npx @puppeteer/browsers install chromedriver@<Chrome-major>" >&2
    exit 1
  fi

  DRIVER_LOG="$(mktemp "${TMPDIR:-/tmp}/allround-chromedriver.XXXXXX")"
  "$chromedriver_bin" --port=4444 > "$DRIVER_LOG" 2>&1 &
  DRIVER_PID=$!

  driver_ready=false
  for _ in {1..50}; do
    if curl --fail --silent --max-time 1 \
      http://127.0.0.1:4444/status >/dev/null 2>&1; then
      driver_ready=true
      break
    fi
    sleep 0.1
  done
  if ! $driver_ready; then
    echo "ChromeDriver가 제한 시간 안에 시작되지 않았습니다." >&2
    sed -n '1,120p' "$DRIVER_LOG" >&2
    exit 1
  fi

  (
    cd app
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/auth_navigation_test.dart \
      --device-id=web-server \
      --driver-port=4444 \
      --headless \
      --timeout=300 \
      --dart-define-from-file="$runtime_config"
  )
else
  (
    cd app
    flutter test integration_test/auth_navigation_test.dart \
      -d "$DEVICE" \
      --dart-define-from-file="$runtime_config"
  )
fi
