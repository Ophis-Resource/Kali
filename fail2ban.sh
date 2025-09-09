#!/bin/bash
echo "#########################################################"
echo "Starting Fail2Ban Installation and Configuration..."
echo "#########################################################"
# Install required packages first
echo "1. Installing bsdmainutils and nginx..."
echo "#########################################################"
sudo apt update
sudo apt install -y bsdmainutils nginx
echo "#########################################################"
# Check if NGINX is installed and running
echo "2. Checking NGINX service status..."
if ! sudo systemctl is-active --quiet nginx; then
    echo "⚠️ NGINX service is not currently running. Attempting to start NGINX..."
    sudo systemctl start nginx
else
    echo "✅ NGINX is running."
fi
# Install Fail2Ban if not already installed
if ! dpkg -l | grep -qw fail2ban; then
    echo "🛡️ Installing Fail2Ban..."
    sudo apt install -y fail2ban
else
    echo "✅ Fail2Ban is already installed."
fi
echo "#########################################################"
# Check Fail2Ban service status
echo "3. Checking Fail2Ban service status..."
if ! sudo systemctl is-active --quiet fail2ban; then
    echo "⚠️ Fail2Ban service is not currently running."
else
    echo "✅ Fail2Ban is running."
fi
echo "#########################################################"
# Ensure jail.local exists
echo "4. Ensuring jail.local exists..."
sudo touch /etc/fail2ban/jail.local
sudo chmod 644 /etc/fail2ban/jail.local

# Add [DEFAULT] block if not already there
if grep -q "\[DEFAULT\]" /etc/fail2ban/jail.local; then
    echo "🛑 [DEFAULT] section already exists. Skipping."
else
    echo "🔧 Adding [DEFAULT] configuration..."
    echo "[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5" | sudo tee -a /etc/fail2ban/jail.local
fi

# Add SSH jail if not already there
if grep -q "\[sshd\]" /etc/fail2ban/jail.local; then
    echo "🛑 [sshd] section already exists. Skipping."
else
    echo "🔧 Adding [sshd] jail..."
    echo "
[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s" | sudo tee -a /etc/fail2ban/jail.local
fi

# Add NGINX HTTP Auth jail if not already there
if grep -q "\[nginx-http-auth\]" /etc/fail2ban/jail.local; then
    echo "🛑 [nginx-http-auth] section already exists. Skipping."
else
    echo "🔧 Adding [nginx-http-auth] jail..."
    echo "
[nginx-http-auth]
enabled = true
port = http,https
logpath = %(nginx_error_log)s" | sudo tee -a /etc/fail2ban/jail.local
fi
echo "#########################################################"
# Enable and restart Fail2Ban
echo "5. Enabling and starting Fail2Ban service..."
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
echo "#########################################################"
# Verify Fail2Ban is running
echo "6. Verifying Fail2Ban status..."
if sudo systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2Ban is active and running."
else
    echo "❌ Fail2Ban failed to start. Check logs for details:"
    sudo journalctl -xeu fail2ban
    exit 1
fi
echo "#########################################################"
# List available filters
echo "📂 Listing available filters..."
ls /etc/fail2ban/filter.d | column
echo "#########################################################"
# Show nginx-http-auth filter
echo "7. Displaying nginx-http-auth filter content..."
cat /etc/fail2ban/filter.d/nginx-http-auth.conf | head -n 20

# Wait until fail2ban.sock exists (max 5 seconds)
for i in {1..5}; do
  if [ -S /var/run/fail2ban/fail2ban.sock ]; then
    break
  fi
  sleep 1
done

# Then get jail status
sudo fail2ban-client status || echo "❌ Unable to fetch jail status."
echo "#########################################################"
echo "✅ Fail2Ban Installation and Configuration Complete!"
echo "#########################################################"
echo "📜 Last Fail2Ban log entries:"
echo "#########################################################"
sudo systemctl status fail2ban
echo "#########################################################"
sudo tail -n 10 /var/log/fail2ban.log
echo "#########################################################"
