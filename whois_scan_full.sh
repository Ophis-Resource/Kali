#!/bin/bash
# Full Whois scan: works with IP, domain, and subdomain

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <ip-or-domain>"
    exit 1
fi

TARGET=$1
LOGFILE="$LOG_DIR/whois.log"
OUTPUT="$OUTPUT_DIR/whois_output.txt"
> "$LOGFILE"

print_star_box2 "Whois - Full"
print_separator2

# IP regex (IPv4 only here)
if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[*] Detected IPv4 address: $TARGET" | tee -a "$LOGFILE"
    run_command "whois $TARGET | tee -a $OUTPUT" "whois IP"
else
    echo "[*] Detected domain or subdomain: $TARGET" | tee -a "$LOGFILE"

    # Extract base domain
    BASE_DOMAIN=$(echo "$TARGET" | awk -F. '{n=split($0, a, "."); if (n>=2) print a[n-1]"."a[n]; else print $0}')
    
    echo "[*] Extracted base domain: $BASE_DOMAIN" | tee -a "$LOGFILE"
    run_command "whois $BASE_DOMAIN | tee -a $OUTPUT" "whois domain"
fi

print_separator2
echo "[*] Whois complete. Output saved to $OUTPUT"
