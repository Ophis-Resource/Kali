#!/bin/bash
# set -o errexit
# set -o nounset
# set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <url> [wordlist]"
  exit 1
fi

URL=$1
WORDLIST=${2:-/usr/share/wordlists/dirb/common.txt}
LOGFILE="$LOG_DIR/ffuf.log"
OUTPUT="$OUTPUT_DIR/ffuf_output.txt"

# Clear previous log file
> "$LOGFILE"

# Prepend http:// if URL does not start with http or https
if [[ "$URL" != http* ]]; then
  URL="http://$URL"
fi

print_star_box2 "ffuf scans"
print_separator2

# ffuf specific command
FFUF_CMD="sudo ffuf -u $URL/FUZZ -w $WORDLIST -o $OUTPUT -t 20 -v -fc 404"
echo "Running: $FFUF_CMD" | tee -a "$LOGFILE"

# Run ffuf with provided parameters and log output
run_command "$FFUF_CMD" "ffuf basic"

print_separator2
echo "[*] ffuf done. Output: $OUTPUT"
