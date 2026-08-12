#!/usr/bin/env bash
#
# Run Codex with Taskmaster same-process continuation (expect transport).
#
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$SOURCE_DIR/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
INJECTOR="$SCRIPT_DIR/hooks/inject-continue-codex.sh"
EXPECT_BRIDGE="$SCRIPT_DIR/hooks/run-codex-expect-bridge.exp"
ORIGINAL_ARGS=("$@")

resolve_real_codex_bin() {
  local candidate
  local wrapper_path="$SOURCE_PATH"
  local wrapper_cmd="$HOME/.codex/bin/codex-taskmaster"
  local codex_shim="$HOME/.codex/bin/codex"

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$candidate" in
      "$wrapper_path"|"$wrapper_cmd"|"$codex_shim")
        continue
        ;;
    esac
    # Skip shell script wrappers (superset, etc.) — only accept real binaries
    if head -c 2 "$candidate" 2>/dev/null | grep -q '^#!'; then
      continue
    fi
    echo "$candidate"
    return 0
  done < <(which -a codex 2>/dev/null | awk '!seen[$0]++')

  return 1
}

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH." >&2
  exit 4
fi

REAL_CODEX_BIN="${TASKMASTER_REAL_CODEX_BIN:-}"
if [[ -z "$REAL_CODEX_BIN" ]]; then
  REAL_CODEX_BIN="$(resolve_real_codex_bin || true)"
fi
if [[ -z "$REAL_CODEX_BIN" ]] || [[ ! -x "$REAL_CODEX_BIN" ]]; then
  echo "Could not resolve real codex binary. Set TASKMASTER_REAL_CODEX_BIN." >&2
  exit 4
fi

is_known_subcommand() {
  case "$1" in
    exec|e|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|a|fork|cloud|features|help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Pass through for non-interactive codex command families and generic help/version.
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  case "$arg" in
    -h|--help|-V|--version)
      exec "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
      ;;
  esac
done

first_non_option=""
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  if [[ "$arg" == "--" ]]; then
    break
  fi
  if [[ "$arg" == -* ]]; then
    continue
  fi
  first_non_option="$arg"
  break
done
if [[ -n "$first_non_option" ]] && is_known_subcommand "$first_non_option"; then
  exec "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
fi

PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PASSTHROUGH_ARGS+=("$1")
        shift
      done
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ! -x "$INJECTOR" ]]; then
  echo "Missing executable injector script: $INJECTOR" >&2
  exit 4
fi

if [[ ! -x "$EXPECT_BRIDGE" ]]; then
  echo "Missing executable expect bridge: $EXPECT_BRIDGE" >&2
  exit 4
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "expect is required." >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 4
fi

build_log_path() {
  local timestamp

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$-1"
  echo "$HOME/.codex/log/taskmaster-session-${timestamp}.jsonl"
}

prepare_log_env() {
  local log_path="$1"
  mkdir -p "$(dirname "$log_path")"
  : > "$log_path"
  export CODEX_TUI_RECORD_SESSION=1
  export CODEX_TUI_SESSION_LOG_PATH="$log_path"
}

cleanup_background() {
  local pid="$1"
  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

run_injector_supervisor() {
  local log_path="$1"
  local queue_dir="$2"
  local state_dir="$3"
  local stop_file="$4"
  local runtime_log="$5"
  local status=0

  while [[ ! -f "$stop_file" ]]; do
    TASKMASTER_RUNTIME_LOG="$runtime_log" "$INJECTOR" \
      --follow \
      --log "$log_path" \
      --emit-dir "$queue_dir" \
      --state-dir "$state_dir" || status=$?

    if [[ -f "$stop_file" ]]; then
      break
    fi

    printf '[%s] supervisor_restart injector_status=%s log=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$log_path" >>"$runtime_log"
    sleep 1
  done
}

run_expect_mode() {
  local log_path
  local queue_dir
  local state_dir
  local stop_file
  local runtime_log
  local injector_pid=""
  local codex_exit=0

  log_path="$(build_log_path)"
  prepare_log_env "$log_path"

  queue_dir="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-emit.XXXXXX")"
  state_dir="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-state.XXXXXX")"
  stop_file="$state_dir/stop"
  runtime_log="$state_dir/runtime.log"

  run_injector_supervisor "$log_path" "$queue_dir" "$state_dir" "$stop_file" "$runtime_log" &
  injector_pid="$!"
  # Details written to runtime_log; no stderr noise on startup

  if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
    "$EXPECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" "${PASSTHROUGH_ARGS[@]}" || codex_exit=$?
  else
    "$EXPECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" || codex_exit=$?
  fi

  : > "$stop_file"
  cleanup_background "$injector_pid"
  rm -rf "$queue_dir"
  rm -rf "$state_dir"

  return "$codex_exit"
}

run_expect_mode
exit $?
