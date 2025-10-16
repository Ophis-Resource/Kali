#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -ne 1 ]; then echo "Usage: $0 <host-or-domain>"; exit 1; fi
TARGET=$1
HTTP="http://$TARGET"
HTTPS="https://$TARGET"
LOGFILE="$LOG_DIR/whatweb.log"
OUTPUT="$OUTPUT_DIR/whatweb_scan_output.txt"
> "$LOGFILE"

print_star_box2 "WhatWeb - variations"
print_separator2

run_command "whatweb -v $TARGET | tee -a $OUTPUT" "whatweb -v $TARGET"
print_separator2
run_command "whatweb $HTTP | tee -a $OUTPUT" "whatweb http"
print_separator2
run_command "whatweb -v $HTTP | tee -a $OUTPUT" "whatweb -v http"
print_separator2
run_command "whatweb -t 10 $HTTP | tee -a $OUTPUT" "whatweb -t 10 http"
print_separator2
run_command "whatweb -p 'title,server' $HTTP | tee -a $OUTPUT" "whatweb -p title,server http"
print_separator2

echo "[*] ======== HTTP SCANS COMPLETED, NOW STARTING HTTPS SCANS ========"

run_command "whatweb $HTTPS | tee -a $OUTPUT" "whatweb https"
print_separator2
run_command "whatweb -v $HTTPS | tee -a $OUTPUT" "whatweb -v https"
print_separator2
run_command "whatweb -t 10 $HTTPS | tee -a $OUTPUT" "whatweb -t 10 https"
print_separator2
run_command "whatweb -p 'title,server' $HTTPS | tee -a $OUTPUT" "whatweb -p title,server https"
print_separator2
echo "[*] WhatWeb done. Output: $OUTPUT"
