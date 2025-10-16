#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# Determine base directory and load config/helpers
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$DIR/config.sh"
source "$DIR/utils.sh"

# === Input Validation ===
if [ $# -lt 1 ]; then
  echo "Usage: $0 <host-or-domain>"
  exit 1
fi

TARGET=$1
LOGFILE="$LOG_DIR/ping.log"
OUTPUT="$OUTPUT_DIR/ping_output.txt"
> "$LOGFILE"
> "$OUTPUT"

print_star_box2 "Ping Scan for: $TARGET"
print_separator2

### 🟡 Check if system has `ping`
if ! command -v ping >/dev/null 2>&1; then
  echo "❌ ERROR: 'ping' command not found!" | tee -a "$OUTPUT"
  exit 1
fi

### ✅ Try ping and extract timing
if ping -c 4 -W 3 "$TARGET" > "$LOGFILE" 2>&1; then
  echo "✅ Host $TARGET is reachable via ICMP." | tee -a "$OUTPUT"

  echo -e "\n--- Ping Output ---\n" >> "$OUTPUT"
  cat "$LOGFILE" >> "$OUTPUT"

  # Extract and print ICMP timing
  echo -e "\n--- ICMP Timing Analysis ---" >> "$OUTPUT"
  grep -Eo 'min/avg/max/mdev = .* ms' "$LOGFILE" >> "$OUTPUT" || echo "Timing data not available." >> "$OUTPUT"
else
  echo "⚠️ Ping failed for $TARGET — trying traceroute fallback..." | tee -a "$OUTPUT"

  ### 🔄 Fallback: Traceroute if available
  if command -v traceroute >/dev/null 2>&1; then
    echo -e "\n--- Traceroute Output ---\n" >> "$OUTPUT"
    traceroute "$TARGET" >> "$OUTPUT" 2>&1 || echo "Traceroute failed." >> "$OUTPUT"
  elif command -v tracepath >/dev/null 2>&1; then
    echo -e "\n--- Tracepath Output ---\n" >> "$OUTPUT"
    tracepath "$TARGET" >> "$OUTPUT" 2>&1 || echo "Tracepath failed." >> "$OUTPUT"
  else
    echo "⚠️ Neither 'traceroute' nor 'tracepath' is installed." >> "$OUTPUT"
  fi

  ### 🪟 Fallback: Test-Connection on WSL/Windows
  if grep -iq 'microsoft' /proc/version 2>/dev/null; then
    echo -e "\n--- Test-Connection (PowerShell) Output ---\n" >> "$OUTPUT"
    powershell.exe -Command "Test-Connection -ComputerName $TARGET -Count 4" >> "$OUTPUT" 2>&1 || echo "Test-Connection failed." >> "$OUTPUT"
  fi
fi

print_separator2
echo "[*] ✅ Ping scan finished. Output saved to: $OUTPUT"
