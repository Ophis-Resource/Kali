#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
SPLUNK_FORWARDER_VERSION="9.4.2"
SPLUNK_BUILD="e9664af3d956"
DEB_PKG="splunkforwarder-${SPLUNK_FORWARDER_VERSION}-${SPLUNK_BUILD}-linux-amd64.deb"
DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_FORWARDER_VERSION}/linux/${DEB_PKG}"
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_PASSWORD="Splunk@Prod123"
SPLUNK_USER="admin"
NGINX_HOST="$(hostname)"

# Ask user for Splunk server IP
read -p "Enter the Splunk server's IP address: " SPLUNK_HOST
SPLUNK_PORT="9997"

wget -O "$DEB_PKG" "$DOWNLOAD_URL"
sudo dpkg -i "$DEB_PKG"

sudo "${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt --seed-passwd "$SPLUNK_PASSWORD"

sudo "${SPLUNK_HOME}/bin/splunk" add forward-server "${SPLUNK_HOST}:${SPLUNK_PORT}" \
  -auth "${SPLUNK_USER}:${SPLUNK_PASSWORD}"

sudo mkdir -p "${SPLUNK_HOME}/etc/system/local"
sudo tee "${SPLUNK_HOME}/etc/system/local/inputs.conf" > /dev/null <<CONF
[monitor:///var/log/nginx/access.log]
disabled = false
index = main
sourcetype = nginx_access_combined
host = ${NGINX_HOST}

[monitor:///var/log/nginx/error.log]
disabled = false
index = main
sourcetype = error_log
host = ${NGINX_HOST}
CONF

sudo "${SPLUNK_HOME}/bin/splunk" restart

echo
sudo "${SPLUNK_HOME}/bin/splunk" list forward-server
echo "Forwarder configured to send logs to ${SPLUNK_HOST}:${SPLUNK_PORT}"
