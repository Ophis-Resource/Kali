#!/usr/bin/env bash
# commix wrapper - no authorization guard
# Usage: ./commix_wrapper.sh <url>
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
# shellcheck source=/dev/null
source "$DIR/config.sh"
# shellcheck source=/dev/null
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <url>"
  exit 1
fi

TARGET=$1

# Auto-prefix http:// if no scheme is provided
if ! [[ "$TARGET" =~ ^https?:// ]]; then
  echo "[*] No URL scheme detected, prefixing with http://"
  TARGET="https://$TARGET"
fi

# Ensure log/output directories exist
: "${LOG_DIR:=./logs}"
: "${OUTPUT_DIR:=./output}"
mkdir -p -- "$LOG_DIR" "$OUTPUT_DIR"

LOGFILE="$LOG_DIR/commix.log"
CANONICAL_OUTPUT="$OUTPUT_DIR/commix_output.txt"

# Temp outputs for this run
RUN_OUT="$(mktemp --tmpdir commix_run.XXXXXX.txt)"
RUN_LOG="$(mktemp --tmpdir commix_run.XXXXXX.log)"
cleanup() {
  rm -f -- "$RUN_OUT" "$RUN_LOG"
}
trap cleanup EXIT

# Simple URL sanity check (permissive)
if ! [[ "$TARGET" =~ ^https?://[^[:space:]]+ ]]; then
  echo "[!] Target does not look like a valid URL: '$TARGET'" | tee -a "$LOGFILE"
  exit 2
fi

# Check commix binary
if ! command -v commix >/dev/null 2>&1; then
  echo "[!] 'commix' executable not found in PATH. Install commix or adjust PATH." | tee -a "$LOGFILE"
  exit 3
fi

print_star_box2 "Commix Wrapper"
print_separator2

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$TIMESTAMP] Starting commix run for $TARGET" | tee -a "$LOGFILE"

COMMIX_CMD=(commix -u "$TARGET" --batch --level=1 --risk=1)

echo "[$TIMESTAMP] Command: ${COMMIX_CMD[*]}" >>"$RUN_LOG"

# Execute the command
if ! "${COMMIX_CMD[@]}" >"$RUN_OUT" 2>>"$RUN_LOG"; then
  echo "[!] commix exited with non-zero status. See $RUN_LOG for details." | tee -a "$LOGFILE"
else
  echo "[*] commix finished successfully." | tee -a "$LOGFILE"
fi

# Append output to canonical files
{
  printf "==== commix run %s for %s ====\n" "$TIMESTAMP" "$TARGET"
  cat "$RUN_OUT"
  printf "\n\n"
} >>"$CANONICAL_OUTPUT"

{
  printf "==== commix run log %s for %s ====\n" "$TIMESTAMP" "$TARGET"
  cat "$RUN_LOG"
  printf "\n\n"
} >>"$LOGFILE"

echo "[*] commix finished. Output appended to: $CANONICAL_OUTPUT" | tee -a "$LOGFILE"
