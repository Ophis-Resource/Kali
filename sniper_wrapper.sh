#!/bin/bash
# sniper wrapper - guarded (aggressive)
# set -o errexit
# set -o nounset
# set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then echo "Usage: $0 <target>"; exit 1; fi
TARGET=$1
LOGFILE="$LOG_DIR/sniper.log"
OUTPUT="$OUTPUT_DIR/sniper_output.txt"
> "$LOGFILE"

print_star_box2 "Sniper (guarded)"
print_separator2

if [ "${I_HAVE_AUTHORIZATION:-0}" != "1" ]; then
  echo "[!] sniper is guarded. Set I_HAVE_AUTHORIZATION=1 to run." | tee -a "$LOGFILE"
  echo "Dry-run:" | tee -a "$LOGFILE"
  echo "sniper -t $TARGET -m recon" | tee -a "$LOGFILE"
  exit 0
fi

run_command "sudo sniper -t $TARGET -m recon | tee -a $OUTPUT" "sniper recon"
print_separator2
run_command "sudo sniper -t $TARGET -m web | tee -a $OUTPUT" "sniper web" || true
print_separator2

echo "[*] sniper done. Output: $OUTPUT"
