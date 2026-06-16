#!/usr/bin/env bash
set -euo pipefail

echo "[*] Stopping nginx if running..."
sudo systemctl stop nginx || true
sudo pkill -9 nginx || true

echo "[*] Purging nginx packages..."
sudo apt purge -y nginx nginx-common nginx-core || true
sudo apt autoremove -y

echo "[*] Verifying nginx binary removal..."
which nginx >/dev/null 2>&1 && echo "[!] nginx still exists" || echo "[OK] nginx binary removed"

echo "[*] Removing nginx directories..."
sudo rm -rf \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /usr/share/nginx \
  /run/nginx

echo "[*] Removing ModSecurity nginx module if present..."
sudo rm -f /etc/nginx/modules/ngx_http_modsecurity_module.so || true

echo "[*] Checking for loaded ModSecurity libraries..."
ldconfig -p | grep -i modsecurity || true

echo "[*] Removing ModSecurity files and libraries..."
sudo rm -rf \
  /usr/local/modsecurity \
  /usr/local/lib/libmodsecurity* \
  /usr/local/include/modsecurity \
  /usr/local/bin/modsecurity* \
  /usr/lib/libmodsecurity* \
  /usr/include/modsecurity \
  /usr/share/modsecurity \
  /etc/nginx/modsec

echo "[*] Refreshing linker cache..."
sudo ldconfig

echo "[*] Verifying ModSecurity removal..."
ldconfig -p | grep -i modsecurity || echo "[OK] libmodsecurity removed"

echo "[*] Removing leftover build/install artifacts..."
sudo rm -rf \
  ~/modsecinstall.sh \
  ~/ModSecurity \
  ~/nginx-* \
  ~/ModSecurity-nginx

echo "[*] Final verification..."
nginx -v >/dev/null 2>&1 && echo "[!] nginx still detected" || echo "[OK] nginx not found"

echo "[✓] Cleanup complete."
