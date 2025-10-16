#!/usr/bin/env bash
# dotdotpwn wrapper - guarded

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh" || true
source "$DIR/utils.sh" || true

if [ $# -lt 1 ]; then
  echo "Usage: $0 <target>"
  exit 1
fi

TARGET=$1
LOGFILE="${LOG_DIR:-$DIR/logs}/dotdotpwn.log"
OUTPUT="${OUTPUT_DIR:-$DIR/output}/dotdotpwn_output.txt"
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$OUTPUT")"
: > "$LOGFILE"
: > "$OUTPUT"

print_star_box2 "dotdotpwn (guarded)"
print_separator2

if [ "${I_HAVE_AUTHORIZATION:-0}" != "1" ]; then
  echo "[!] dotdotpwn is guarded. Set I_HAVE_AUTHORIZATION=1 to run." | tee -a "$LOGFILE"
  echo "Dry-run command (example):" | tee -a "$LOGFILE"
  echo "printf '\\n' | dotdotpwn -m http -h $TARGET" | tee -a "$LOGFILE"
  exit 0
fi

if ! command -v dotdotpwn &>/dev/null; then
  echo "[!] dotdotpwn not found in PATH." | tee -a "$LOGFILE"
  exit 2
fi

run_command "printf '\\n' | dotdotpwn -m http -h \"$TARGET\" | tee -a \"$OUTPUT\"" "dotdotpwn scan"

print_separator2
echo "[*] dotdotpwn finished. Output: $OUTPUT" | tee -a "$LOGFILE"
