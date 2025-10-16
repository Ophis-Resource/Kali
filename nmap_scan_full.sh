#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then echo "Usage: $0 <host-or-domain>"; exit 1; fi
TARGET=$1
LOGFILE="$LOG_DIR/nmap.log"
OUTPUT="$OUTPUT_DIR/nmap_output.txt"
> "$LOGFILE"

print_star_box2 "Nmap - many scans"
print_separator2
run_command "nmap $TARGET | tee -a $OUTPUT" "nmap basic"
print_separator2
run_command "nmap -sS $TARGET | tee -a $OUTPUT" "nmap -sS"
print_separator2
run_command "nmap -sT $TARGET | tee -a $OUTPUT" "nmap -sT"
print_separator2
run_command "nmap -sU $TARGET | tee -a $OUTPUT" "nmap -sU" || true
print_separator2
run_command "nmap -p 22,80,443 $TARGET | tee -a $OUTPUT" "nmap specific ports"
print_separator2
run_command "nmap -p- $TARGET | tee -a $OUTPUT" "nmap all ports"
print_separator2
run_command "nmap -sV $TARGET | tee -a $OUTPUT" "nmap -sV"
print_separator2
run_command "nmap -O $TARGET | tee -a $OUTPUT" "nmap -O"
print_separator2
run_command "nmap -A $TARGET | tee -a $OUTPUT" "nmap -A"
print_separator2
run_command "nmap -T4 $TARGET | tee -a $OUTPUT" "nmap -T4"
print_separator2
run_command "nmap --script vuln $TARGET | tee -a $OUTPUT" "nmap --script vuln" || true
print_separator2
echo "[*] nmap done. Output: $OUTPUT"
