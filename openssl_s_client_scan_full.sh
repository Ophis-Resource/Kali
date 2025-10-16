#!/bin/bash

# Exit on most errors, except in custom error handling
# set -o errexit
# set -o nounset
# set -o pipefail

# Load configuration and utilities
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

# === Input Validation ===
if [ $# -lt 1 ]; then
  echo "Usage: $0 <host[:port]>"
  exit 1
fi

TARGET=$1
HOST=$(echo "$TARGET" | cut -d: -f1)
PORT=$(echo "$TARGET" | cut -s -d: -f2)

# Default to port 443 if not specified
if [ -z "$PORT" ]; then
  PORT=443
fi

LOGFILE="$LOG_DIR/openssl.log"
OUTPUT="$OUTPUT_DIR/openssl_output.txt"

# Clean logs
> "$LOGFILE"
> "$OUTPUT"

# === Banner ===
print_star_box2 "OpenSSL s_client Scan for $HOST:$PORT"
print_separator2

# === Basic OpenSSL Connection Test ===
print_star_box2 "Testing connectivity to $HOST:$PORT with timeout"
if ! timeout 15 openssl s_client -connect "$HOST:$PORT" < /dev/null > /dev/null 2>&1; then
  echo "❌ ERROR: Unable to connect to $HOST:$PORT via OpenSSL" | tee -a "$OUTPUT"
  echo "❌ Tip: This may be due to blocked outbound traffic from the pipeline agent" | tee -a "$OUTPUT"
  echo "Running fallback check with curl..."
  if ! curl -sI --connect-timeout 10 "https://$HOST" > /dev/null; then
    echo "❌ ERROR: curl also failed to reach https://$HOST" | tee -a "$OUTPUT"
    exit 1
  else
    echo "✅ curl succeeded — HTTPS is reachable from here" | tee -a "$OUTPUT"
  fi
else
  echo "✅ Connection to $HOST:$PORT successful via OpenSSL" | tee -a "$OUTPUT"
fi
print_separator2

# === OpenSSL Scans ===

run_command "openssl s_client -connect $HOST:$PORT -showcerts < /dev/null | tee -a $OUTPUT" "s_client -showcerts"
print_separator2

run_command "openssl s_client -connect $HOST:$PORT -tls1_2 -servername $HOST < /dev/null | tee -a $OUTPUT" "s_client -tls1_2"
print_separator2

run_command "openssl s_client -connect $HOST:$PORT -tls1_3 -servername $HOST < /dev/null | tee -a $OUTPUT" "s_client -tls1_3"
print_separator2

# === Cipher-Specific Tests ===
CIPHERS=(
  'ECDHE-RSA-AES128-GCM-SHA256'
  'ECDHE-RSA-AES256-GCM-SHA384'
  'AES128-SHA'
)

for C in "${CIPHERS[@]}"; do
  run_command "openssl s_client -cipher '$C' -connect $HOST:$PORT < /dev/null | tee -a $OUTPUT" "s_client cipher $C" || true
  print_separator2
done

# === Completion Message ===
echo "[*] ✅ OpenSSL scan complete for $HOST:$PORT"
echo "[*] 📄 Output saved to: $OUTPUT"
