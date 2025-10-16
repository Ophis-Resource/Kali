#!/bin/bash
# nosqlmap wrapper - guarded
# set -o errexit
# set -o nounset
# set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then echo "Usage: $0 <url> [params]"; exit 1; fi
TARGET=$1
PARAMS=${2:-}
LOGFILE="$LOG_DIR/nosqlmap.log"
OUTPUT="$OUTPUT_DIR/nosqlmap_output.txt"
> "$LOGFILE"

print_star_box2 "nosqlmap (guarded)"
print_separator2

if [ "${I_HAVE_AUTHORIZATION:-0}" != "1" ]; then
  echo "[!] nosqlmap is guarded. Set I_HAVE_AUTHORIZATION=1 to run." | tee -a "$LOGFILE"
  echo "Dry-run examples:" | tee -a "$LOGFILE"
  echo "nosqlmap -u \"$TARGET\" -p \"$PARAMS\"" | tee -a "$LOGFILE"
  exit 0
fi

run_command "nosqlmap -u \"$TARGET\" -p \"$PARAMS\" --batch | tee -a $OUTPUT" "nosqlmap basic"
print_separator2

echo "[*] nosqlmap finished. Output: $OUTPUT"
