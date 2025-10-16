#!/bin/bash

# ------------------------------
# Dependency checker
# ------------------------------
REQUIRED_COMMANDS=(whois nmap curl)  # Add any other tools your scripts use
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -ne 0 ]; then
    echo "[!] Missing required commands: ${MISSING_COMMANDS[*]}"
    echo "[*] Installing missing dependencies via apt..."
    sudo apt update
    for cmd in "${MISSING_COMMANDS[@]}"; do
        sudo apt install -y "$cmd"
    done
else
    echo "[*] All dependencies are installed."
fi
# ------------------------------
# End dependency checker
# ------------------------------

# Get the directory where this script resides
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source config and utils using absolute paths
source "$DIR/config.sh"
source "$DIR/utils.sh"

# Check for required argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <IP-or-Domain>"
    exit 1
fi

TARGET=$1

# Create output directories if they don't exist
mkdir -p "$LOG_DIR" "$OUTPUT_DIR"

# Launch each tool in tools/ directory in background
for tool in "$DIR/tools/"*.sh; do
    if [ -f "$tool" ]; then
        echo "[*] Launching $tool in background"
        bash "$tool" "$TARGET" &
    fi
done

# Wait for all background processes to finish
wait

echo "[*] All scans completed."
