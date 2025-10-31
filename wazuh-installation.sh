#!/bin/bash
set -e

echo "[+] Cleaning old Wazuh setup..."
sudo rm -rf ~/wazuh-docker/ || true
sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true
sudo docker system prune -af --volumes -f

echo "[+] Cloning Wazuh Docker repository (v4.14.0)..."
cd ~
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.0
cd wazuh-docker/single-node/

echo "[+] Generating self-signed certificates..."
sudo docker-compose -f generate-indexer-certs.yml run --rm generator

echo "[+] Checking generated certificates..."
sudo ls -l ./config/wazuh_indexer_ssl_certs/

echo "[+] Deploying Wazuh single-node stack..."
sudo docker-compose up -d

echo "[+] Deployment started. Containers coming up..."
echo "Use: watch sudo docker ps -a"
echo "Access dashboard after ~2 minutes:"
echo "URL: https://<YOUR_VM_PUBLIC_IP>"
echo "Username: admin"
echo "Password: SecretPassword"
