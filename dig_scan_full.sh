#!/usr/bin/env bash
# dig wrapper - multiple DNS queries with safe failure handling
# Usage: ./dig_wrapper.sh <domain or IP>

# Uncomment if you want strict safety, but can be dangerous with failing commands
# set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
# shellcheck source=/dev/null
source "$DIR/config.sh"
# shellcheck source=/dev/null
source "$DIR/utils.sh"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <domain or IP>"
  exit 1
fi

TARGET=$1
: "${LOG_DIR:=./logs}"
: "${OUTPUT_DIR:=./output}"
mkdir -p -- "$LOG_DIR" "$OUTPUT_DIR"

LOGFILE="$LOG_DIR/dig.log"
OUTPUT="$OUTPUT_DIR/dig_output.txt"

> "$LOGFILE"
> "$OUTPUT"

print_star_box2 "dig - many queries"
print_separator2

run_command "dig $TARGET | tee -a $OUTPUT" "dig" || true
print_separator2

run_command "dig $TARGET A | tee -a $OUTPUT" "dig A" || true
print_separator2

run_command "dig $TARGET AAAA | tee -a $OUTPUT" "dig AAAA" || true
print_separator2

run_command "dig $TARGET MX | tee -a $OUTPUT" "dig MX" || true
print_separator2

run_command "dig $TARGET NS | tee -a $OUTPUT" "dig NS" || true
print_separator2

run_command "dig $TARGET TXT | tee -a $OUTPUT" "dig TXT" || true
print_separator2

run_command "dig $TARGET CNAME | tee -a $OUTPUT" "dig CNAME" || true
print_separator2

run_command "dig $TARGET SOA | tee -a $OUTPUT" "dig SOA" || true
print_separator2

run_command "dig +short $TARGET | tee -a $OUTPUT" "dig +short" || true
print_separator2

run_command "dig +trace $TARGET | tee -a $OUTPUT" "dig +trace" || true
print_separator2

# Only run reverse lookup if the input looks like an IPv4 address
if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  run_command "dig -x $TARGET | tee -a $OUTPUT" "dig -x" || true
  print_separator2
fi

run_command "dig $TARGET +dnssec +multiline | tee -a $OUTPUT" "dig +dnssec +multiline" || true
print_separator2

echo "[*] dig scans done. Output: $OUTPUT"
