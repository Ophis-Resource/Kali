#!/bin/bash

# Absolute paths
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

# Function to check if the input is an IP address
is_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1
}

if [ $# -ne 1 ]; then
    echo "Usage: $0 <IP-or-Domain>"
    exit 1
fi

TARGET=$1
LOGFILE="$LOG_DIR/nslookup.log"
OUTPUT="$OUTPUT_DIR/nslookup_output.txt"
> "$LOGFILE"

print_star_box2 "Nslookup scan tool"
print_separator2

# Check if the input is an IP address or domain
if is_ip "$TARGET"; then
    # If IP, perform reverse lookup (PTR record)
    echo "Handling IP address: $TARGET"
    print_separator2
    run_command "nslookup $TARGET | tee -a $OUTPUT" "Nslookup IP address"
    print_separator2
    run_command "nslookup -type=PTR $TARGET | tee -a $OUTPUT" "Nslookup reverse lookup (PTR)"
else
    # If domain, perform normal nslookup queries
    echo "Handling domain name: $TARGET"
    print_separator2
    run_command "nslookup $TARGET | tee -a $OUTPUT" "Nslookup scan"
    print_separator2
    run_command "nslookup -type=A $TARGET | tee -a $OUTPUT" "Nslookup A record"
    print_separator2
    run_command "nslookup -query=MX $TARGET | tee -a $OUTPUT" "Nslookup MX record"
    print_separator2
    run_command "nslookup -server=8.8.8.8 $TARGET | tee -a $OUTPUT" "Nslookup using Google DNS"
    print_separator2
    run_command "nslookup -timeout=5 $TARGET | tee -a $OUTPUT" "Nslookup with timeout"
    print_separator2
    run_command "nslookup -recurse $TARGET | tee -a $OUTPUT" "Nslookup recursive"
    print_separator2
    run_command "nslookup -debug $TARGET | tee -a $OUTPUT" "Nslookup debug"
    run_command "nslookup -class=IN $TARGET | tee -a $OUTPUT" "Nslookup class IN"
fi

echo "[*] Nslookup scan completed. Output saved to $OUTPUT"
