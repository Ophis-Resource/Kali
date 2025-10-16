#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

usage() {
    echo "Usage: $0 <domain-or-ip>"
    exit 1
}

# IPv4 validation (rejects octets >255)
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

if [ $# -ne 1 ]; then usage; fi
TARGET=$1

LOGFILE="$LOG_DIR/nslookup.log"
OUTPUT="$OUTPUT_DIR/nslookup_output.txt"
> "$LOGFILE"

print_star_box2 "Nslookup - variations"
print_separator2

# Helper to run a possibly-failing command safely (log exit code & continue)
safe_run() {
    # usage: safe_run "description" command [arg...]
    local desc="$1"; shift
    echo "[*] Running (safe): $desc" | tee -a "$OUTPUT"
    print_separator2
    # disable errexit for this block in case utils or environment has it
    set +e
    # run the command; use "$@" to preserve arguments safely
    "$@" 2>&1 | tee -a "$OUTPUT"
    local rc=${PIPESTATUS[0]:-0}
    set -e 2>/dev/null || true
    if [ "$rc" -ne 0 ]; then
        echo "[!] Command returned non-zero exit code: $rc (non-fatal)" | tee -a "$OUTPUT"
    fi
    print_separator2
}

if is_ipv4 "$TARGET"; then
    echo "[*] Detected IPv4 address: $TARGET" | tee -a "$OUTPUT"
    print_separator2

    # Use safe_run for potentially NXDOMAIN-producing reverse lookups.
    safe_run "nslookup (reverse)" nslookup "$TARGET"
    safe_run "nslookup -type=PTR (tolerant)" nslookup -type=PTR "$TARGET"
    safe_run "dig -x (PTR) +noall +answer" dig -x "$TARGET" +noall +answer
    safe_run "host (reverse)" host "$TARGET"

    # Google DNS variant — some nslookup variants require different invocation so use safe_run fallback
    if command -v nslookup >/dev/null 2>&1; then
        # Try the '-server=' form first; if it fails, try the interactive-style fallback
        set +e
        nslookup -server=8.8.8.8 "$TARGET" >/dev/null 2>&1
        rc_try=$?
        set -e 2>/dev/null || true
        if [ $rc_try -eq 0 ]; then
            safe_run "nslookup -server=8.8.8.8 (reverse)" nslookup -server=8.8.8.8 "$TARGET"
        else
            safe_run "nslookup using Google DNS (fallback interactive style)" sh -c "printf 'server 8.8.8.8\n$TARGET\nexit\n' | nslookup"
        fi
    fi

    echo "[*] IP handling complete. PTR (reverse DNS) may be absent (NXDOMAIN) — that's normal." | tee -a "$OUTPUT"

else
    echo "[*] Detected domain name: $TARGET" | tee -a "$OUTPUT"
    print_separator2

    # Keep using run_command for domain queries (behaves as your framework expects)
    run_command "nslookup $TARGET 2>&1 | tee -a $OUTPUT" "nslookup" || true
    print_separator2
    run_command "nslookup -type=A $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -type=A" || true
    print_separator2
    run_command "nslookup -query=MX $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -query=MX" || true
    print_separator2
    run_command "nslookup -timeout=5 $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -timeout=5" || true
    print_separator2

    # Google DNS handling (tolerant)
    if nslookup >/dev/null 2>&1; then
      if nslookup -server=8.8.8.8 "$TARGET" >/dev/null 2>&1; then
        run_command "nslookup -server=8.8.8.8 $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -server=8.8.8.8" || true
      else
        run_command "printf 'server 8.8.8.8\n$TARGET\nexit\n' | nslookup 2>&1 | tee -a $OUTPUT" "nslookup using Google DNS (fallback)" || true
      fi
      print_separator2
    fi

    run_command "nslookup -debug $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -debug" || true
    print_separator2
    # run_command "nslookup -class=IN $TARGET 2>&1 | tee -a $OUTPUT" "nslookup -class=IN" || true
    # print_separator2

    echo "[*] nslookup domain queries complete. Output saved to $OUTPUT" | tee -a "$OUTPUT"
fi

echo "[*] nslookup run finished."
