#!/usr/bin/env bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

usage() {
    echo "Usage: $0 <IP-or-domain-or-subdomain>"
    echo "Environment:"
    echo "  TIMEOUT_SEC - per-tool timeout in seconds (default: 300)"
    exit 1
}

# ---------- Config ----------
TIMEOUT_SEC="${TIMEOUT_SEC:-300}"   # default 5 minutes per heavy tool
SUBLISTER_BIN="${SUBLISTER_BIN:-sublist3r}"  # allow override
# ----------------------------

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

# Basic domain-like heuristic (contains a dot and not purely numeric)
is_domain_like() {
    local v=$1
    [[ $v == *.* ]] && ! is_ipv4 "$v"
}

# Try to extract base domain using tldextract (if installed). If not available, fall back to NS walking.
get_base_domain() {
    local fqdn="$1"
    fqdn="${fqdn%.}"   # remove trailing dot

    # If tldextract available, use it (best accuracy)
    if command -v python3 >/dev/null 2>&1; then
        # try import tldextract in a subshell; avoid failing the script if not installed
        python3 - <<'PY' 2>/dev/null || true
import sys
try:
    import tldextract
    fqdn = sys.argv[1]
    ext = tldextract.extract(fqdn)
    if ext.domain and ext.suffix:
        print(f"{ext.domain}.{ext.suffix}")
    else:
        # fallback: print fqdn (caller will fallback further)
        print(fqdn)
except Exception:
    print(sys.argv[1])
PY
        rc=$?
        if [ $rc -eq 0 ]; then
            # capture printed value from python call above
            # (we invoked Python inline which printed to stdout already, but we need a single-call return)
            :
        fi
    fi

    # If no tldextract / or the python block above didn't print usable value, do NS-based discovery:
    # Walk labels from left -> right and query NS; first label+... that *has* NS -> we've found zone.
    IFS='.' read -r -a labels <<< "$fqdn"
    local n=${#labels[@]}
    if (( n <= 1 )); then
        echo "$fqdn"
        return
    fi

    # Try progressively higher-level domains (start at full FQDN -> reduce)
    for ((i=0; i<=n-2; i++)); do
        domain=""
        for ((j=i; j<n; j++)); do
            if [ -z "$domain" ]; then
                domain="${labels[j]}"
            else
                domain="${domain}.${labels[j]}"
            fi
        done

        # query NS records (short output)
        nsr=$(dig +short NS "$domain" 2>/dev/null || true)
        if [ -n "$nsr" ]; then
            echo "$domain"
            return
        fi

        # if we are down to two labels and still nothing, break to fallback
        if (( n - i == 2 )); then
            break
        fi
    done

    # fallback to last-two labels
    echo "${labels[n-2]}.${labels[n-1]}"
}

# wrapper to call run_command if present, otherwise eval
do_run() {
    local desc="$1"; shift
    local cmd="$*"
    if declare -f run_command >/dev/null 2>&1; then
        run_command "$cmd" "$desc" || true
    else
        echo "[*] (no run_command) $desc: $cmd"
        bash -c "$cmd" || true
    fi
}

if [ $# -ne 1 ]; then usage; fi
TARGET="$1"

LOGFILE="$LOG_DIR/sublister.log"
OUTPUT="$OUTPUT_DIR/sublister_output.txt"
> "$LOGFILE" 2>/dev/null || true
> "$OUTPUT" 2>/dev/null || true

print_star_box2 "sublister - variants"
print_separator2

if is_ipv4 "$TARGET"; then
    echo "[*] Detected IPv4 address: $TARGET" | tee -a "$OUTPUT" "$LOGFILE"
    print_separator2

    # PTR / reverse lookups (concise + verbose variants)
    do_run "host (reverse lookup)" "host $TARGET 2>&1 | tee -a \"$OUTPUT\""
    print_separator2
    do_run "dig -x (PTR) +noall +answer" "dig -x $TARGET +noall +answer 2>&1 | tee -a \"$OUTPUT\""
    print_separator2
    do_run "nslookup -type=PTR" "nslookup -type=PTR $TARGET 2>&1 | tee -a \"$OUTPUT\""
    print_separator2

    # Try reverse using Google DNS
    do_run "nslookup (google DNS)" "nslookup -server=8.8.8.8 $TARGET 2>&1 | tee -a \"$OUTPUT\""
    print_separator2

    # Attempt a best-effort passive hint: reverse PTR names -> extract possible domain candidates
    ptrs=$(dig -x "$TARGET" +short 2>/dev/null || true)
    if [ -n "$ptrs" ]; then
        echo "[*] PTR records found (candidates):" | tee -a "$OUTPUT" "$LOGFILE"
        echo "$ptrs" | sed 's/\.$//' | tee -a "$OUTPUT" "$LOGFILE"
    else
        echo "[*] No PTR records found for IP." | tee -a "$OUTPUT" "$LOGFILE"
    fi

    echo "[*] IP handling complete. Subdomain enumeration requires a domain." | tee -a "$OUTPUT" "$LOGFILE"

elif is_domain_like "$TARGET"; then
    echo "[*] Detected domain/subdomain: $TARGET" | tee -a "$OUTPUT" "$LOGFILE"
    print_separator2

    # Resolve base domain (zone cut): prefer tldextract when available, else NS-walk / fallback.
    BASE_DOMAIN=$(get_base_domain "$TARGET")
    # If python+tldextract printed result earlier, capture that output if present:
    # (attempt to re-run tldextract to get deterministic result)
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<PY 2>/dev/null
import sys
try:
    import tldextract
    ext = tldextract.extract(sys.argv[1])
    if ext.domain and ext.suffix:
        print(f"{ext.domain}.{ext.suffix}")
except Exception:
    pass
PY "$TARGET" | read -r tld_res || true
    if [ -n "$tld_res" ]; then
        BASE_DOMAIN="$tld_res"
    fi

    echo "[*] Using base domain for enumeration: $BASE_DOMAIN" | tee -a "$OUTPUT" "$LOGFILE"
    if [ "$BASE_DOMAIN" != "$TARGET" ]; then
        echo "[*] NOTE: Input was a subdomain; running enumeration against base domain: $BASE_DOMAIN" | tee -a "$OUTPUT" "$LOGFILE"
    fi
    print_separator2

    # -------- sublist3r runs (wrapped by timeout) ----------
    # Basic passive scan
    if command -v "$SUBLISTER_BIN" >/dev/null 2>&1; then
        do_run "sublist3r basic (passive) (timeout=${TIMEOUT_SEC}s)" "timeout ${TIMEOUT_SEC}s $SUBLISTER_BIN -d $BASE_DOMAIN 2>&1 | tee -a \"$OUTPUT\""
        print_separator2

        # Save to file with -o (but still ensure timeout)
        do_run "sublist3r save to file (timeout=${TIMEOUT_SEC}s)" "timeout ${TIMEOUT_SEC}s $SUBLISTER_BIN -d $BASE_DOMAIN -o \"$OUTPUT\" 2>&1 | tee -a \"$LOGFILE\""
        print_separator2

        # --no-wildcards avoids wildcard noise (may speed up)
        do_run "sublist3r --no-wildcards (timeout=${TIMEOUT_SEC}s)" "timeout ${TIMEOUT_SEC}s $SUBLISTER_BIN -d $BASE_DOMAIN --no-wildcards 2>&1 | tee -a \"$OUTPUT\""
        print_separator2

        # Optional brute force: comment-in if you want but it's expensive; kept with timeout
        # do_run "sublist3r brute (timeout=${TIMEOUT_SEC}s)" "timeout ${TIMEOUT_SEC}s $SUBLISTER_BIN -d $BASE_DOMAIN --brute 2>&1 | tee -a \"$OUTPUT\""
        # print_separator2
    else
        echo "[!] sublist3r ($SUBLISTER_BIN) not found in PATH. Skipping sublist3r." | tee -a "$OUTPUT" "$LOGFILE"
    fi

    # Optionally: run findomain if installed (fast)
    if command -v findomain >/dev/null 2>&1; then
        do_run "findomain (fast) (timeout=${TIMEOUT_SEC}s)" "timeout ${TIMEOUT_SEC}s findomain -t $BASE_DOMAIN 2>&1 | tee -a \"$OUTPUT\""
        print_separator2
    fi

    echo "[*] sublist3r stage finished. Results: $OUTPUT" | tee -a "$OUTPUT" "$LOGFILE"

else
    echo "[!] Input doesn't look like a valid IPv4 address or domain/subdomain: '$TARGET'" | tee -a "$LOGFILE"
    usage
fi

print_separator2
echo "[*] script finished." | tee -a "$OUTPUT" "$LOGFILE"
