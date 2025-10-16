#!/bin/bash
# ================================
# config.sh – shared settings
# ================================

# Stop on error, undefined vars, or failed pipes
set -o errexit
set -o nounset
set -o pipefail

# Directories (relative to repo root)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/tools/logs"
OUTPUT_DIR="$BASE_DIR/tools/output"
JSON_DIR="$OUTPUT_DIR/json"

# Ensure dirs exist
mkdir -p "$LOG_DIR" "$OUTPUT_DIR" "$JSON_DIR"

# Timestamp function
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# JSON writing helper
# Usage: write_json "tool" "target" "status" "rc" "summary"
# Example: write_json "ping" "example.com" "ok" 0 '{"avg_rtt_ms":42.3}'
write_json() {
  local tool=$1
  local target=$2
  local status=$3
  local rc=$4
  local summary_json=$5
  local file="$JSON_DIR/${tool}_meta.json"

  cat > "$file" <<EOF
{
  "tool": "$tool",
  "target": "$target",
  "status": "$status",
  "rc": $rc,
  "timestamp": "$(timestamp)",
  "summary": $summary_json,
  "raw_output": "${tool}_output.txt"
}
EOF
  echo "[*] Wrote JSON metadata to $file"
}
