#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -ne 1 ]; then echo "Usage: $0 <host-or-ip>"; exit 1; fi
TARGET=$1
LOGFILE="$LOG_DIR/traceroute.log"
OUTPUT="$OUTPUT_DIR/traceroute_output.txt"
> "$LOGFILE"

print_star_box2 "Traceroute (ICMP/UDP/TCP variants)"
print_separator2

# classic traceroute
if command -v traceroute >/dev/null 2>&1; then
  run_command "traceroute $TARGET | tee -a $OUTPUT" "traceroute"
  print_separator2
fi

# tcptraceroute if available (TCP)
if command -v tcptraceroute >/dev/null 2>&1; then
  run_command "sudo tcptraceroute $TARGET | tee -a $OUTPUT" "tcptraceroute (TCP)"
  print_separator2
fi

# traceroute with TCP (--tcp on modern inetutils)
if command -v tracepath >/dev/null 2>&1; then
  run_command "tracepath $TARGET | tee -a $OUTPUT" "tracepath"
  print_separator2
fi

echo "[*] traceroute done. Output: $OUTPUT"
