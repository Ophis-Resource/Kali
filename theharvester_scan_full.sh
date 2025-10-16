#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

# Default values
TIMEOUT_SEC="${TIMEOUT_SEC:-300}"
MAX_RESULTS="${MAX_RESULTS:-200}"

usage() {
    echo "Usage: $0 <domain-or-subdomain> [data-source]"
    echo "Examples:"
    echo "  $0 sisschools.org all"
    echo "  $0 dev.example.com google"
    exit 1
}

# Validate IPv4 (reject invalid octets)
is_ipv4() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$ip"
    for o in "${octets[@]}"; do
        if (( o < 0 || o > 255 )); then return 1; fi
    done
    return 0
}

# Extract base domain using tldextract or fallback
get_base_domain() {
    local fqdn="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<EOF 2>/dev/null
import sys
try:
    import tldextract
    e = tldextract.extract(sys.argv[1])
    if e.domain and e.suffix:
        print(f"{e.domain}.{e.suffix}")
    else:
        print(sys.argv[1])
except:
    print(sys.argv[1])
EOF
    else
        # fallback: remove first label
        echo "$fqdn" | awk -F. '{print $(NF-1)"."$NF}'
    fi
}

if [ $# -lt 1 ]; then usage; fi

TARGET=$1
DATA=${2:-all}

LOGFILE="$LOG_DIR/theharvester.log"
OUTPUT="$OUTPUT_DIR/theharvester_output.txt"
> "$LOGFILE" 2>/dev/null || true
> "$OUTPUT" 2>/dev/null || true

print_star_box2 "theHarvester"
print_separator2

if is_ipv4 "$TARGET"; then
    echo "[*] Input is an IP: $TARGET" | tee -a "$OUTPUT"
    echo "[!] theHarvester is meant for domain-based enumeration. Skipping." | tee -a "$OUTPUT"
    exit 0
fi

# Strip down to base domain if it's a subdomain
BASE_DOMAIN=$(get_base_domain "$TARGET")

if [[ "$BASE_DOMAIN" != "$TARGET" ]]; then
    echo "[*] Input appears to be a subdomain. Using base domain: $BASE_DOMAIN" | tee -a "$OUTPUT"
else
    echo "[*] Using domain: $BASE_DOMAIN" | tee -a "$OUTPUT"
fi
print_separator2

# Run theHarvester basic
run_command "timeout ${TIMEOUT_SEC}s theHarvester -d $BASE_DOMAIN -b $DATA | tee -a $OUTPUT" "theHarvester basic" || true
print_separator2

# Extended run (limit results, may take longer)
run_command "timeout ${TIMEOUT_SEC}s theHarvester -d $BASE_DOMAIN -b all -l $MAX_RESULTS | tee -a $OUTPUT" "theHarvester extended" || true
print_separator2

echo "[*] theHarvester done. Output: $OUTPUT"
