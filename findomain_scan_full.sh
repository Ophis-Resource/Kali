#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

usage() {
    echo "Usage: $0 <domain_or_ip>"
    exit 1
}

# Validate IPv4 (reject octets >255)
is_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for o in "${octets[@]}"; do
            if (( o < 0 || o > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Find the "base" domain by walking up the FQDN and checking for NS records.
# Example: dev-erp.sisschools.org -> sisschools.org (if sisschools.org has NS records)
get_base_domain_by_ns() {
    local fqdn="$1"

    # Normalize: remove trailing dot if present
    fqdn="${fqdn%.}"

    # Split into labels
    IFS='.' read -r -a labels <<< "$fqdn"
    local n=${#labels[@]}

    # If only 1 label, return as-is
    if (( n <= 1 )); then
        echo "$fqdn"
        return
    fi

    # Try progressively higher-level domains starting from the full FQDN:
    # dev.aaa.example.co.uk -> try dev.aaa.example.co.uk => aaa.example.co.uk => example.co.uk => co.uk
    # stop when we find NS records or when we reach two labels (fallback).
    for (( i=0; i<=n-2; i++ )); do
        # Build domain from labels[i..end]
        local domain=""
        for (( j=i; j<n; j++ )); do
            if [ -z "$domain" ]; then
                domain="${labels[j]}"
            else
                domain="${domain}.${labels[j]}"
            fi
        done

        # Query NS records (use dig to keep output easy to parse)
        # +noall +answer => only answers, easier to test
        ns_output=$(dig +short NS "$domain" 2>/dev/null || true)
        if [ -n "$ns_output" ]; then
            # Found NS records for this domain -> treat as base
            echo "$domain"
            return
        fi

        # If we're down to two labels and still haven't found NS, break and fallback
        if (( n - i == 2 )); then
            break
        fi
    done

    # Fallback: return last two labels (best-effort)
    echo "${labels[n-2]}.${labels[n-1]}"
}

if [ $# -ne 1 ]; then usage; fi
TARGET=$1

LOGFILE="$LOG_DIR/findomain.log"
OUTPUT="$OUTPUT_DIR/findomain_output.txt"
> "$LOGFILE"
> "$OUTPUT" || true

print_star_box2 "findomain"
print_separator2

if is_ipv4 "$TARGET"; then
    echo "[*] Detected IPv4 address: $TARGET" | tee -a "$OUTPUT" "$LOGFILE"
    print_separator2

    # Do some IP-oriented reconnaissance (reverse PTR) and note that findomain is domain-only
    echo "[*] Running reverse lookups for IP (dig + host + nslookup)..." | tee -a "$OUTPUT" "$LOGFILE"
    dig -x "$TARGET" +noall +answer 2>&1 | tee -a "$OUTPUT" "$LOGFILE" || true
    host "$TARGET" 2>&1 | tee -a "$OUTPUT" "$LOGFILE" || true
    nslookup "$TARGET" 2>&1 | tee -a "$OUTPUT" "$LOGFILE" || true

    echo "[*] No subdomain enumeration performed for IP addresses. Consider nmap/enum4linux/etc for IP-based checks." | tee -a "$OUTPUT" "$LOGFILE"
else
    echo "[*] Detected domain/subdomain: $TARGET" | tee -a "$OUTPUT" "$LOGFILE"
    print_separator2

    # Determine base domain (prefer NS-based discovery; fallback to last-two-label heuristic)
    BASE_DOMAIN=$(get_base_domain_by_ns "$TARGET")
    echo "[*] Resolved base domain for enumeration: $BASE_DOMAIN" | tee -a "$OUTPUT" "$LOGFILE"

    # Inform if the base domain differs from the input (common when subdomain passed)
    if [ "$BASE_DOMAIN" != "$TARGET" ]; then
        echo "[*] NOTE: Input was subdomain; using base domain '$BASE_DOMAIN' for findomain enumeration." | tee -a "$OUTPUT" "$LOGFILE"
    fi

    print_separator2

    # Run findomain against the base domain. Capture output (append) and log return code.
    if command -v findomain >/dev/null 2>&1; then
        # run_command wrapper used by your framework - keep it consistent
        run_command "findomain -t $BASE_DOMAIN 2>&1 | tee -a $OUTPUT" "findomain -t $BASE_DOMAIN" || true
    else
        echo "[!] findomain not found in PATH. Please install findomain or add it to PATH." | tee -a "$OUTPUT" "$LOGFILE"
        exit 1
    fi

    print_separator2

    echo "[*] findomain run finished. Results appended to: $OUTPUT" | tee -a "$OUTPUT" "$LOGFILE"
fi

print_separator2
