#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then echo "Usage: $0 <host> [port]"; exit 1; fi
HOST=$1
PORT=${2:-443}
LOGFILE="$LOG_DIR/sslscan.log"
OUTPUT="$OUTPUT_DIR/sslscan_output.txt"
> "$LOGFILE"

print_star_box2 "sslscan"
print_separator2

run_command "sslscan ${HOST}:${PORT} | tee -a $OUTPUT" "sslscan default"
print_separator2
run_command "sslscan --no-sslv2 --no-sslv3 ${HOST}:${PORT} | tee -a $OUTPUT" "sslscan disable SSLv2/SSLv3"
print_separator2
for TLS in tls1 tls1_1 tls1_2 tls1_3; do
  run_command "sslscan --tls=${TLS} ${HOST}:${PORT} | tee -a $OUTPUT" "sslscan ${TLS}" || true
  print_separator2
done

echo "[*] sslscan done. Output: $OUTPUT"
