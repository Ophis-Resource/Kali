#!/usr/bin/env bash
# DNS Enumeration and Intelligence Collection Script (Enhanced)
# Non-fatal execution with structured logging and delegation/recursion handling.

set -o errexit
set -o pipefail
set -o nounset

# --- Variables ---
TARGET=${1:-}
if [ -z "$TARGET" ]; then
    echo "[ERROR] Usage: $0 <target>"
    exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT="$OUTPUT_DIR/dnsenum_${TARGET}_${TIMESTAMP}.txt"
LOGFILE="$LOG_DIR/dnsenum_${TARGET}_${TIMESTAMP}.log"

# Public recursive resolvers used as fallbacks
PUBLIC_RESOLVERS=(1.1.1.1 8.8.8.8)

# --- Utility Functions ---
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_ipv6() { [[ "$1" =~ : ]]; }

safe_run() {
    local desc="$1"; shift
    local cmd=("$@")
    echo "[$(timestamp)] [*] $desc: ${cmd[*]}" | tee -a "$OUTPUT" "$LOGFILE"
    echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"
    if ! "${cmd[@]}" 2>&1 | tee -a "$OUTPUT" "$LOGFILE"; then
        local exitcode=$?
        echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"
        echo "[$(timestamp)] [!] $desc returned exit code $exitcode (non-fatal)" | tee -a "$OUTPUT" "$LOGFILE"
    fi
    echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"
}

# Run dig against a specific resolver (or system if no resolver provided)
dig_with_resolver() {
    local resolver="${1:-}" ; shift || true
    local args=( "$@" )
    if [ -n "$resolver" ]; then
        dig @"$resolver" "${args[@]}"
    else
        dig "${args[@]}"
    fi
}

# Get delegated NS from a public recursive resolver (parent delegation)
get_delegation_ns() {
    local resolver="${1:-1.1.1.1}"
    dig_with_resolver "$resolver" +short NS "$TARGET" | sed 's/\.$//'
}

# Verify each authoritative NS by asking for SOA (directly to the NS)
verify_authoritative_ns() {
    local ns
    local ok=0
    for ns in "$@"; do
        # ask the NS for SOA of the zone directly (timeout short)
        if dig @"$ns" "$TARGET" SOA +short +time=3 | grep -q '[A-Za-z0-9]'; then
            echo "$ns: OK" | tee -a "$OUTPUT" "$LOGFILE"
            ok=1
        else
            echo "$ns: no response or no SOA" | tee -a "$OUTPUT" "$LOGFILE"
        fi
    done
    return $ok
}

# If parent delegation is missing or resolvers can't recurse, fall back to public resolvers + trace
resolve_or_fallback() {
    # Try to get NS from a public resolver
    echo "[$(timestamp)] [INFO] Checking parent delegation (public resolver: ${PUBLIC_RESOLVERS[0]})" | tee -a "$OUTPUT" "$LOGFILE"
    local ns_list
    ns_list=$(get_delegation_ns "${PUBLIC_RESOLVERS[0]}")

    if [ -z "$ns_list" ]; then
        echo "[$(timestamp)] [WARN] Parent delegation returned no NS records via ${PUBLIC_RESOLVERS[0]}." | tee -a "$OUTPUT" "$LOGFILE"
        echo "[$(timestamp)] [INFO] Running dig +trace to find where chain breaks." | tee -a "$OUTPUT" "$LOGFILE"
        safe_run "dig +trace for $TARGET" dig +trace +nodnssec "$TARGET"
        # After trace, try other public resolvers
        ns_list=$(get_delegation_ns "${PUBLIC_RESOLVERS[1]}")
    fi

    if [ -n "$ns_list" ]; then
        echo "[$(timestamp)] [INFO] Delegation NS (from public resolver):" | tee -a "$OUTPUT" "$LOGFILE"
        echo "$ns_list" | tee -a "$OUTPUT" "$LOGFILE"

        # verify authoritatives
        mapfile -t ns_array <<< "$ns_list"
        if verify_authoritative_ns "${ns_array[@]}"; then
            echo "[$(timestamp)] [INFO] Found at least one responding authoritative NS." | tee -a "$OUTPUT" "$LOGFILE"
            # We'll prefer using public recursive resolvers for queries to avoid recursion problems
            RESOLVER_TO_USE="${PUBLIC_RESOLVERS[0]}"
            return 0
        else
            echo "[$(timestamp)] [WARN] Authoritative NS did not respond to SOA queries. Will continue with trace & public resolvers." | tee -a "$OUTPUT" "$LOGFILE"
            RESOLVER_TO_USE="${PUBLIC_RESOLVERS[0]}"
            return 0
        fi
    else
        echo "[$(timestamp)] [ERROR] Could not determine delegation NS from public resolvers. Using trace output and public resolvers for queries." | tee -a "$OUTPUT" "$LOGFILE"
        RESOLVER_TO_USE="${PUBLIC_RESOLVERS[0]}"
        return 1
    fi
}

# --- Start ---
echo "[$(timestamp)] Starting dnsenum_scan_full for target: $TARGET"
echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"

# --- Handle IP Targets Gracefully ---
set +e
{
    if is_ipv4 "$TARGET" || is_ipv6 "$TARGET"; then
        echo "[$(timestamp)] [INFO] Detected IP: $TARGET — running light reverse checks and exiting success." | tee -a "$OUTPUT" "$LOGFILE"

        safe_run "dig -x $TARGET (PTR)" dig -x "$TARGET" +noall +answer || true
        safe_run "host $TARGET (reverse)" host "$TARGET" || true
        safe_run "nslookup $TARGET (reverse)" nslookup "$TARGET" || true

        if command -v curl >/dev/null 2>&1; then
            safe_run "RDAP lookup for $TARGET" bash -c "curl -fsS 'https://rdap.org/ip/$TARGET'" || true
        fi

        echo "[$(timestamp)] [INFO] IP checks complete. Exiting with success (0)." | tee -a "$OUTPUT" "$LOGFILE"
        exit 0
    fi
}
set -e

# --- Domain Intelligence ---
# First, check delegation and figure out whether we need fallbacks
RESOLVER_TO_USE=""
if ! resolve_or_fallback; then
    echo "[$(timestamp)] [WARN] Delegation detection incomplete; continuing with available fallbacks." | tee -a "$OUTPUT" "$LOGFILE"
fi

# If delegation is clearly OK, run dnsenum normally; otherwise avoid depending on recursion and:
# - run dig +trace (already done if delegation missing)
# - run dnsenum but expect it might fail; still run safe_run so failures are non-fatal
if [ -z "$RESOLVER_TO_USE" ]; then
    # No special resolver chosen — system resolver likely fine
    safe_run "dnsenum: Basic enumeration for $TARGET" dnsenum "$TARGET"
    safe_run "dnsenum: Reverse lookup of IP addresses for $TARGET" dnsenum -r "$TARGET"
    safe_run "dnsenum: Disable reverse DNS lookup for $TARGET" dnsenum --no-reverse "$TARGET"
    safe_run "dnsenum: Discover subdomains for $TARGET" dnsenum --subdomains "$TARGET"
else
    # We have a public recursive resolver to use for queries — use that for proactive checks and brute force,
    # and still attempt dnsenum (it may use system resolver). Keep it non-fatal.
    echo "[$(timestamp)] [INFO] Using public resolver $RESOLVER_TO_USE for recursive queries and brute-force." | tee -a "$OUTPUT" "$LOGFILE"

    safe_run "dig +trace for $TARGET (trace fallback)" dig +trace +nodnssec "$TARGET" || true

    # Run dnsenum as best-effort (non-fatal)
    safe_run "dnsenum (best-effort) for $TARGET" dnsenum "$TARGET" || true

    safe_run "dnsenum -r (best-effort)" dnsenum -r "$TARGET" || true
    safe_run "dnsenum --no-reverse (best-effort)" dnsenum --no-reverse "$TARGET" || true
    safe_run "dnsenum --subdomains (best-effort)" dnsenum --subdomains "$TARGET" || true
fi

# Amass (passive) — doesn't need recursion from local resolver usually
if command -v amass >/dev/null 2>&1; then
    safe_run "Amass passive enumeration" amass enum -passive -d "$TARGET" -o "$OUTPUT_DIR/amass_${TARGET}.txt"
fi

# --- Wordlist-based subdomain brute-force ---
WORDLIST="/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt"
if [ -f "$WORDLIST" ]; then
    # Use chosen resolver (public) if set, otherwise system resolver
    local_resolver_arg=""
    if [ -n "${RESOLVER_TO_USE:-}" ]; then
        local_resolver_arg="${RESOLVER_TO_USE}"
        echo "[$(timestamp)] [INFO] Using resolver ${local_resolver_arg} for brute-force dig queries." | tee -a "$OUTPUT" "$LOGFILE"
    fi

    safe_run "DNS brute force using $WORDLIST" bash -c "
    while read -r sub; do
        fqdn=\${sub}.${TARGET}
        if [ -n \"$local_resolver_arg\" ]; then
            dig @${local_resolver_arg} +short \$fqdn | grep -v '^$' && echo \$fqdn
        else
            dig +short \$fqdn | grep -v '^$' && echo \$fqdn
        fi
    done < '$WORDLIST' | tee -a '$OUTPUT_DIR/dnsbrute_${TARGET}.txt'
    "
fi

# --- Final Output ---
echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"
echo "[$(timestamp)] [INFO] DNS enumeration completed successfully for: $TARGET" | tee -a "$OUTPUT" "$LOGFILE"
echo "======================================================================================" | tee -a "$OUTPUT" "$LOGFILE"
exit 0
