#!/usr/bin/env bash
# sqlmap wrapper - guarded (exploit-like)
# Allows args in any order: flags may appear before or after the target.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
# shellcheck source=/dev/null
source "$DIR/config.sh" || true
# shellcheck source=/dev/null
source "$DIR/utils.sh" || true

usage() {
  cat <<EOF
Usage: $0 <target> [sqlmap-args...]
  Target may be a URL (http(s)://...) or a hostname/domain (example.com) or an IP.
  You may provide sqlmap flags anywhere on the command line.
Examples:
  $0 dev-erp.sisschools.org -y
  $0 -y dev-erp.sisschools.org --risk=2 --level=2
  $0 http://example.com/page.php?id=1 --data="id=1" -p id --batch
EOF
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

# Find first arg that is not an option (does not start with '-')
ARGS=("$@")
TARGET=""
REMAINING=()

for a in "${ARGS[@]}"; do
  if [[ "$a" == --* ]]; then
    # long option -> treat as option
    REMAINING+=("$a")
    continue
  fi
  if [[ "$a" == -* ]]; then
    # short option -> treat as option
    REMAINING+=("$a")
    continue
  fi
  # not starting with '-' -> candidate for target
  if [ -z "$TARGET" ]; then
    TARGET="$a"
  else
    # if we've already found a target, treat subsequent non-flag args as options too
    REMAINING+=("$a")
  fi
done

if [ -z "$TARGET" ]; then
  echo "[!] No target detected." >&2
  usage
fi

# If target doesn't look like a URL, prefix with http:// for sqlmap convenience (sqlmap accepts hostnames too,
# but normalizing reduces confusion). Do not prefix if it already has scheme or contains '=' (query string) starting with http.
if [[ ! "$TARGET" =~ ^https?:// ]]; then
  # If TARGET contains a slash or '=' or '?' it's probably a URL path; still prefix scheme if missing.
  TARGET="http://$TARGET"
fi

LOGFILE="${LOG_DIR:-$DIR/logs}/sqlmap.log"
OUTPUT="${OUTPUT_DIR:-$DIR/output}/sqlmap_output.txt"
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$OUTPUT")"
: > "$LOGFILE"
: > "$OUTPUT"

print_star_box2 "sqlmap (guarded)"
print_separator2

# Show how sqlmap will be invoked (dry-run) if not authorized
if [ "${I_HAVE_AUTHORIZATION:-0}" != "1" ]; then
  echo "[!] sqlmap is guarded. Set I_HAVE_AUTHORIZATION=1 to actually run it." | tee -a "$LOGFILE"
  echo "Dry-run: the following sqlmap command would be executed:" | tee -a "$LOGFILE"
  printf "sqlmap -u %q %s --batch --level=1 --risk=1\n" "$TARGET" "${REMAINING[*]}" | tee -a "$LOGFILE"
  echo "If you want to run: export I_HAVE_AUTHORIZATION=1" | tee -a "$LOGFILE"
  exit 0
fi

# Ensure sqlmap exists
if ! command -v sqlmap >/dev/null 2>&1; then
  echo "[!] sqlmap executable not found in PATH. Please install sqlmap or add it to PATH." | tee -a "$LOGFILE"
  exit 2
fi

# Build final command array (preserve quoted args safely)
SQLMAP_CMD=(sqlmap -u "$TARGET" "${REMAINING[@]}" --batch --level=1 --risk=1)

# Log command
echo "[*] Running sqlmap command: ${SQLMAP_CMD[*]}" | tee -a "$LOGFILE"

# Use run_command if available for consistent integration, else run directly
if declare -f run_command >/dev/null 2>&1; then
  # run_command expects a string with command and display name; keep display name short
  CMD_STR="sqlmap -u \"$TARGET\" ${REMAINING[*]} --batch --level=1 --risk=1 | tee -a \"$OUTPUT\""
  run_command "$CMD_STR" "sqlmap basic"
else
  # Direct execution, capture output
  set +e
  "${SQLMAP_CMD[@]}" 2>&1 | tee -a "$OUTPUT" | tee -a "$LOGFILE"
  rc=${PIPESTATUS[0]:-0}
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "[!] sqlmap exited with code $rc. Check logs: $LOGFILE and $OUTPUT" | tee -a "$LOGFILE"
    exit $rc
  fi
fi

print_separator2
echo "[*] sqlmap finished. Output: $OUTPUT (note: destructive options disabled unless explicitly added)" | tee -a "$LOGFILE"
