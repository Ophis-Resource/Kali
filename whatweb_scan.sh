#!/bin/bash

# Absolute paths

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

# Check input parameter
if [ $# -ne 1 ]; then
    echo "Usage: $0 <IP-or-Domain>"
    exit 1
fi

TARGET=$1
LOGFILE="$LOG_DIR/whatweb.log"
OUTPUT="$OUTPUT_DIR/whatweb_scan_output.txt"
> "$LOGFILE"

print_star_box2 "WhatWeb scan tool"
print_separator2

# Run verbose WhatWeb scan (original command)
run_command "whatweb -v $TARGET | tee -a $OUTPUT" "WhatWeb verbose scan"
print_separator2

# Extended scans on HTTP and HTTPS
HTTP_TARGET="http://$TARGET"
HTTPS_TARGET="https://$TARGET"

echo -e "\nRunning WhatWeb scans for both HTTP and HTTPS:"
print_separator2

run_command "whatweb $HTTP_TARGET" "WhatWeb HTTP scan"
print_separator2

run_command "whatweb $HTTPS_TARGET" "WhatWeb HTTPS scan"
print_separator2

run_command "whatweb -v $HTTP_TARGET" "WhatWeb verbose HTTP scan"
print_separator2

run_command "whatweb -v $HTTPS_TARGET" "WhatWeb verbose HTTPS scan"
print_separator2

run_command "whatweb -t 10 $HTTP_TARGET" "WhatWeb HTTP timeout scan"
print_separator2

run_command "whatweb -t 10 $HTTPS_TARGET" "WhatWeb HTTPS timeout scan"
print_separator2

run_command "whatweb -p 'title,server' $HTTP_TARGET" "WhatWeb HTTP title and server scan"
print_separator2

run_command "whatweb -p 'title,server' $HTTPS_TARGET" "WhatWeb HTTPS title and server scan"
print_separator2

echo "[*] WhatWeb scan completed. Output saved to $OUTPUT"
