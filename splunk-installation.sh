#!/usr/bin/env bash

# ==============================================================================
# 🛡️ PRODUCTION-GRADE AUTOMATED SPLUNK 10.x DEPLOYER
# ==============================================================================
# DESCRIPTION:
#   This script automates the deployment of a standalone Splunk Enterprise
#   container using explicit version pinning to guarantee environment safety.
#
# OPERATIONAL PLAYBOOK:
#   - Pinned Tag: Uses '10.0.7' to prevent unexpected rolling major version upgrades.
#   - Version 10 Licensing: Automatically passes both 'SPLUNK_START_ARGS' and
#     'SPLUNK_GENERAL_TERMS' to fulfill Splunk 10's runtime legal agreements.
#   - Dependency Safeguard: Verifies host package layouts dynamically to prevent
#     breaking existing Docker environments (e.g., download.docker.com vs apt).
# ==============================================================================

# Exit immediately on failure, trace undefined variables, mask pipeline errors
set -euo pipefail

print_step() {
  echo -e "\n[*] $1"
}

# === Production Immutable Version Configuration ===
SPLUNK_IMAGE_TAG="10.0.7"

# 1. Capture Credentials Safely (Insulated from bash history leaks)
read -r -s -p "Enter SPLUNK admin password: " SPLUNK_PASSWORD
echo
read -r -s -p "Confirm password: " CONFIRM
echo
[[ "$SPLUNK_PASSWORD" == "$CONFIRM" && -n "$SPLUNK_PASSWORD" ]] || { echo "❌ Password mismatch"; exit 1; }

# === Step 2: Deploy Dependencies safely ===
print_step "Checking and updating required packages..."
sudo apt-get update -y
sudo apt-get install -y curl

# Prevent package tree collision if official Docker engine is already active
if ! command -v docker &>/dev/null; then
  echo "[*] Docker engine not detected. Deploying standard host packages..."
  sudo apt-get install -y docker.io
else
  echo "✅ Docker engine is already active. Bypassing repository installation to prevent tree breakages."
fi

# 3. Clean Outdated Environment Contexts
print_step "Clearing lingering container tracking profiles..."
sudo docker rm -f splunk 2>/dev/null || true

# 4. Execute Sealed Container Layout (Utilizing exact Docker Hub pinned tag)
print_step "Launching Splunk ${SPLUNK_IMAGE_TAG} container layout..."
sudo docker run -d \
  --name splunk \
  -p 8000:8000 -p 8088:8088 -p 9997:9997 \
  --restart always \
  -e "SPLUNK_START_ARGS=--accept-license" \
  -e "SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com" \
  -e "SPLUNK_PASSWORD=${SPLUNK_PASSWORD}" \
  -v splunk_data:/opt/splunk/var \
  -v splunk_etc:/opt/splunk/etc \
  splunk/splunk:${SPLUNK_IMAGE_TAG}

print_step "Waiting for container orchestration engine initialization..."
# Splunk 10 background setup playbooks require initialization padding time
sleep 25

print_step "Current container tracking status:"
sudo docker ps --filter "name=splunk"

print_step "Recent service initialization log history:"
sudo docker logs --tail 20 splunk

# Extract clean system target IP address routing map
TARGET_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

echo "======================================================================"
echo "✅ Splunk ${SPLUNK_IMAGE_TAG} deployment completed successfully."
echo "🖥️ Web UI Target : http://${TARGET_IP}:8000"
echo "👤 User Username : admin"
echo "🔐 Password Base : [As configured during prompt initialization]"
echo "======================================================================"
