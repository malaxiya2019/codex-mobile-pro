#!/usr/bin/env bash
#
# Stop hook: keep firing until the agent emits an explicit done signal.
#
# The stop is allowed only after the transcript contains:
#   TASKMASTER_DONE::<session_id>
#
# Optional env vars:
#   TASKMASTER_MAX          Max number of blocks before allowing stop (default: 0 = infinite)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/taskmaster-compliance-prompt.sh"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
# Expand leading ~ to $HOME (tilde not expanded inside quotes by bash)
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
  SESSION_ID="unknown-session"
fi

# --- skip subagents: they have very short transcripts ---
if [ -f "$TRANSCRIPT" ]; then
  LINE_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "0")
  if [ "$LINE_COUNT" -lt 20 ]; then
    exit 0
  fi
fi

# --- counter ---
COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
MAX=${TASKMASTER_MAX:-0}

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi

transcript_has_done_signal() {
  local transcript_path="$1"
  local done_signal="$2"

  [ -f "$transcript_path" ] || return 1

  tail -400 "$transcript_path" 2>/dev/null \
    | jq -Rr '
        fromjson?
        | select(.type == "response_item" and .payload.type == "message" and .payload.role == "assistant")
        | .payload.content[]?
        | select(.type == "output_text")
        | .text // empty
      ' 2>/dev/null \
    | grep -Fq "$done_signal"
}

# --- done signal detection ---
DONE_SIGNAL="TASKMASTER_DONE::${SESSION_ID}"
HAS_DONE_SIGNAL=false
HAS_RECENT_ERRORS=false

# Check last_assistant_message first (available immediately, unlike transcript)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if echo "$LAST_MSG" | grep -Fq "$DONE_SIGNAL" 2>/dev/null; then
  HAS_DONE_SIGNAL=true
fi

# Fall back to transcript search
if [ "$HAS_DONE_SIGNAL" = false ] && [ -f "$TRANSCRIPT" ]; then
  if transcript_has_done_signal "$TRANSCRIPT" "$DONE_SIGNAL"; then
    HAS_DONE_SIGNAL=true
  fi
fi

if [ -f "$TRANSCRIPT" ]; then
  TAIL_40=$(tail -40 "$TRANSCRIPT" 2>/dev/null || true)
  if echo "$TAIL_40" | grep -qi '"is_error":\s*true' 2>/dev/null; then
    HAS_RECENT_ERRORS=true
  fi
fi

if [ "$HAS_DONE_SIGNAL" = true ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

NEXT=$((COUNT + 1))
echo "$NEXT" > "$COUNTER_FILE"

# Optional escape hatch. Default is infinite (0) so hook keeps firing.
if [ "$MAX" -gt 0 ] && [ "$NEXT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

if [ "$HAS_RECENT_ERRORS" = true ]; then
  PREAMBLE="Recent tool errors were detected. Resolve them before declaring done."
else
  PREAMBLE="Stop is blocked until completion is explicitly confirmed."
fi

if [ "$MAX" -gt 0 ]; then
  LABEL="TASKMASTER (${NEXT}/${MAX})"
else
  LABEL="TASKMASTER (${NEXT})"
fi

# --- reprompt ---
SHARED_PROMPT="$(build_taskmaster_compliance_prompt "$DONE_SIGNAL")"
REASON="${LABEL}: ${PREAMBLE}

${SHARED_PROMPT}"

jq -n --arg reason "$REASON" '{ decision: "block", reason: $reason }'
