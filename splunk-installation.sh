#!/usr/bin/env bash
set -euo pipefail

read -r -s -p "Enter SPLUNK admin password: " SPLUNK_PASSWORD
echo
read -r -s -p "Confirm password: " CONFIRM
echo
[[ "$SPLUNK_PASSWORD" == "$CONFIRM" && -n "$SPLUNK_PASSWORD" ]] || { echo "Password mismatch"; exit 1; }

sudo apt-get update -y
sudo apt-get install -y docker.io curl

sudo docker rm -f splunk 2>/dev/null || true
sudo docker run -d \
  --name splunk \
  -p 8000:8000 -p 8088:8088 -p 9997:9997 \
  -e "SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com" \
  -e "SPLUNK_START_ARGS=--accept-license" \
  -e "SPLUNK_PASSWORD=${SPLUNK_PASSWORD}" \
  --restart always \
  -v splunk_data:/opt/splunk/var \
  -v splunk_etc:/opt/splunk/etc \
  splunk/splunk:latest

echo "Splunk server starting..."
sleep 8
sudo docker ps --filter "name=splunk"
sudo docker logs --tail 100 splunk
echo "Web UI: http://$(hostname -I | awk '{print $1}'):8000  admin / $SPLUNK_PASSWORD"
