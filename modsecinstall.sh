#!/bin/bash

set -e
trap 'echo "❌ Error occurred at line $LINENO: $BASH_COMMAND"; exit 1;' ERR

SCRIPT_START_TIME=$(date +%s)

print_step() {
  echo
  echo "#######################"
  echo "🕒 $(date '+%Y-%m-%d %H:%M:%S') | $1"
  echo "#######################"
}


# === Directories and Versions ===
WORK_DIR="$(pwd)"
MODSEC_DIR="$WORK_DIR/ModSecurity"
RULES_DIR="$MODSEC_DIR/rules"
NGINX_MODULES_DIR="/etc/nginx/modules"
NGINX_CONF="/etc/nginx/nginx.conf"
MODSEC_CONF="$MODSEC_DIR/modsecurity.conf"
OWASP_CRS_VERSION="3.0.2"
UNICODE_MAP_DEST="/etc/nginx/modsec/unicode.mapping"

# === Step 1: Install Required Packages ===
print_step "Step 1: Installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  nginx \
  build-essential \
  autoconf \
  automake \
  libtool \
  pkg-config \
  git \
  wget \
  zlib1g-dev \
  libpcre3-dev \
  libxml2-dev \
  libcurl4-openssl-dev \
  liblua5.3-dev \
  libpcre2-dev \
  libssl-dev \
  libxslt1-dev \
  libgd-dev \
  libgeoip-dev \
  libperl-dev \
  libmaxminddb-dev

# === Step 2: Clone and Build ModSecurity ===
print_step "Step 2: Cloning and building ModSecurity..."
if [ ! -d "$MODSEC_DIR/.git" ]; then
  git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity "$MODSEC_DIR"
  cd "$MODSEC_DIR"
  git submodule init && git submodule update
  ./build.sh
  ./configure
  make -j"$(nproc)"
  sudo make install
else
  echo "✅ ModSecurity already exists"
fi

# === Step 3: Clone ModSecurity-nginx Connector ===
print_step "Step 3: Cloning ModSecurity-nginx..."
if [ ! -d "$MODSEC_DIR/ModSecurity-nginx" ]; then
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git "$MODSEC_DIR/ModSecurity-nginx"
else
  echo "✅ ModSecurity-nginx already exists"
fi

# === Step 4: Download and Extract NGINX Source ===
print_step "Step 4: Downloading NGINX source..."
cd "$MODSEC_DIR"
NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9.]*')
NGINX_TARBALL="nginx-$NGINX_VERSION.tar.gz"
NGINX_TARBALL_URL="http://nginx.org/download/$NGINX_TARBALL"

if ! wget --spider "$NGINX_TARBALL_URL" 2>/dev/null; then
  echo "⚠️ Warning: NGINX source version $NGINX_VERSION may not match an official nginx.org tarball."
fi

if [ ! -f "$NGINX_TARBALL" ]; then
  wget "$NGINX_TARBALL_URL" -O "$NGINX_TARBALL"
fi
if [ ! -d "nginx-$NGINX_VERSION" ]; then
  tar -xvzf "$NGINX_TARBALL"
fi

# === Step 5: Build the NGINX ModSecurity Dynamic Module ===
print_step "Step 5: Building NGINX ModSecurity module..."
cd "$MODSEC_DIR/nginx-$NGINX_VERSION"
./configure --with-compat --add-dynamic-module=../ModSecurity-nginx
make modules

# === Step 6: Copying ModSecurity NGINX module... ===
print_step "Step 6: Copying ModSecurity NGINX module..."
{
  FOUND_MODSEC_MODULE=$(find "$MODSEC_DIR/nginx-$NGINX_VERSION/objs" -type f -name "ngx_http_modsecurity_module.so" | head -n 1)
  if [ -z "$FOUND_MODSEC_MODULE" ]; then
    echo "❌ Error: Could not find compiled ngx_http_modsecurity_module.so"
    exit 1
  fi
  sudo mkdir -p "$NGINX_MODULES_DIR"
  sudo cp "$FOUND_MODSEC_MODULE" "$NGINX_MODULES_DIR/"
  MODSEC_MODULE_PATH="$NGINX_MODULES_DIR/$(basename "$FOUND_MODSEC_MODULE")"
  export MODSEC_MODULE_PATH
  echo "✅ Copied module to: $MODSEC_MODULE_PATH"
}

# === Step 6.1: Ensure ONLY the correct ModSecurity load_module line exists ===
print_step "Step 6.1: Ensuring nginx.conf only loads the correct ModSecurity module..."

# Backup nginx.conf first
sudo cp "$NGINX_CONF" "$NGINX_CONF.bak"

MODSEC_MODULE_LINE='load_module "/etc/nginx/modules/ngx_http_modsecurity_module.so";'

# Remove uncommented modsecurity module lines
sudo sed -i '/^[^#]*load_module\s\+["'\'']\?.*ngx_http_modsecurity_module\.so["'\'']\?;/d' "$NGINX_CONF"

# Insert at top
sudo sed -i "1i$MODSEC_MODULE_LINE" "$NGINX_CONF"

echo "✅ nginx.conf cleaned and correctly updated."

# === Step 8: Fix Unicode Mapping ===
print_step "Step 8: Copying unicode.mapping if needed..."
sudo mkdir -p "$(dirname "$UNICODE_MAP_DEST")"
if [ -f "$MODSEC_DIR/unicode.mapping" ]; then
  cp "$MODSEC_DIR/unicode.mapping" "$UNICODE_MAP_DEST"
else
  echo "❌ unicode.mapping not found!"
  exit 1
fi

# === Step 9: Configure ModSecurity ===
print_step "Step 9: Configuring ModSecurity..."
if [ ! -f "$MODSEC_CONF" ]; then
  cp "$MODSEC_DIR/modsecurity.conf-recommended" "$MODSEC_CONF"
  sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$MODSEC_CONF"
fi

# === Step 10: Setup ModSecurity Rules ===
print_step "Step 10: Creating base ModSecurity rules..."
mkdir -p "$RULES_DIR"
cat <<EOF > "$RULES_DIR/main.conf"
Include $MODSEC_CONF

# Custom Rules
SecRule ARGS:blogtest "@contains test" "id:1111,deny,status:403"
SecRule REQUEST_URI "@beginsWith /admin" "phase:2,t:lowercase,id:2222,deny,msg:'block admin'"
EOF

# === Step 11: Download and Setup OWASP CRS ===
print_step "Step 11: Setting up OWASP CRS..."
cd "$RULES_DIR"
if [ ! -d "owasp-crs" ]; then
  git clone --depth 1 -b v$OWASP_CRS_VERSION https://github.com/coreruleset/coreruleset.git owasp-crs
  cp owasp-crs/crs-setup.conf.example owasp-crs/crs-setup.conf
fi

if ! grep -q "owasp-crs/crs-setup.conf" "$RULES_DIR/main.conf"; then
  cat <<EOF >> "$RULES_DIR/main.conf"

# OWASP CRS
Include $RULES_DIR/owasp-crs/crs-setup.conf
Include $RULES_DIR/owasp-crs/rules/*.conf
EOF
fi

# === Step 12: Reload NGINX ===
print_step "Step 12: Testing and reloading NGINX..."
echo
if sudo nginx -t; then
echo
  if command -v systemctl &>/dev/null; then
    sudo systemctl restart nginx
  else
    sudo nginx -s reload || sudo nginx
  fi
else
  echo "❌ NGINX config test failed!"
  exit 1
fi
echo "#######################################################"
echo
echo "✅ ModSecurity with OWASP CRS installed and configured!"
echo
echo "🛡️ Rules applied from: $RULES_DIR/main.conf"
echo
echo "#######################################################"
SCRIPT_END_TIME=$(date +%s)
TOTAL_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
echo
echo "🎉 Script completed in $TOTAL_TIME seconds."
echo "#######################################################"
echo "make sure to add these 2 lines in the server block after server name in default.conf of nginx"
echo "#######################################################"
echo "modsecurity on;"
echo "modsecurity_rules_file /home/ubuntu/ModSecurity/rules/main.conf;"
echo "#######################################################"
