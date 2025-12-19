#!/usr/bin/env bash
set -euo pipefail

# Patterns to match (full command-line match)
PATTERNS=(
  "webserver.py"
  "http.server 8000"
  "/opt/tsc2/result.sh"
  "http.server 8001"
)

# How long to wait after TERM before escalating to KILL (seconds)
TERM_TIMEOUT=5

# Run in dry-run mode if the first arg is "dry"
DRY_RUN=false
if [[ "${1-}" == "dry" ]]; then
  DRY_RUN=true
  echo "DRY RUN: no signals will actually be sent."
fi

# Function to kill processes matched by pattern
kill_by_pattern() {
  local pattern="$1"
  local matches
  matches="$(pgrep -af -- "$pattern" 2>/dev/null || true)"

  if [[ -z "$matches" ]]; then
    echo "No processes found matching: $pattern"
    return 0
  fi

  echo "Matches for: $pattern"
  echo "$matches"

  local pids
  pids="$(echo "$matches" | awk '{print $1}' | tr '\n' ' ')"

  if $DRY_RUN; then
    echo "DRY RUN: would send SIGTERM to: $pids"
    return 0
  fi

  echo "Sending SIGTERM to: $pids"
  sudo kill $pids || true

  local waited=0
  while (( waited < TERM_TIMEOUT )); do
    sleep 1
    waited=$((waited + 1))
    if ! pgrep -f -- "$pattern" >/dev/null; then
      echo "Processes matching '$pattern' exited after SIGTERM."
      return 0
    fi
  done

  echo "Processes still running for '$pattern' after ${TERM_TIMEOUT}s — sending SIGKILL."
  sudo kill -9 $pids || true

  if pgrep -f -- "$pattern" >/dev/null; then
    echo "Warning: some processes matching '$pattern' still remain after SIGKILL."
    pgrep -af -- "$pattern" || true
  else
    echo "Processes matching '$pattern' killed."
  fi
}

# === MAIN ===
for pat in "${PATTERNS[@]}"; do
  kill_by_pattern "$pat"
done

# --- Cleanup section ---
CLEAN_DIR="/opt/tsc2"

if ! $DRY_RUN; then
  echo "Cleaning up files in $CLEAN_DIR ..."
  sudo rm -f "$CLEAN_DIR"/dump.json "$CLEAN_DIR"/server.log "$CLEAN_DIR"/*.txt 2>/dev/null || true
  echo "Cleanup complete."
else
  echo "DRY RUN: would remove JSON, log, and text files from $CLEAN_DIR"
fi

echo "Done."
