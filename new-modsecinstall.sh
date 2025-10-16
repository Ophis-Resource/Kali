#!/bin/bash

# ====================================================================================
#
#             ModSecurity + OWASP CRS for NGINX - Automated Installer Script
#
# ====================================================================================
#
# Description:
#   This script automates the full installation and configuration of ModSecurity v3
#   and the OWASP Core Rule Set (CRS) for NGINX on a Debian/Ubuntu system.
#
# Features:
#   - Installs all necessary build dependencies
#   - Clones and compiles ModSecurity and its NGINX connector
#   - Builds the ModSecurity dynamic NGINX module
#   - Installs OWASP CRS and configures it with custom rules
#   - Automatically updates nginx.conf to load the module
#   - Ensures correct unicode mapping
#   - Uses robust error handling and time tracking
#
# ====================================================================================

# --- Script Configuration ---
set -e
trap 'echo -e "\033[0;31m❌ Error occurred at line $LINENO: $BASH_COMMAND\033[0m"; exit 1;' ERR
SCRIPT_START_TIME=$(date +%s)

# --- Color and Logging Definitions ---
readonly NC='\033[0m'       # No Color
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
print_step()  {
  echo
  echo -e "${CYAN}###############################${NC}"
  echo -e "🕒 $(date '+%Y-%m-%d %H:%M:%S') | $1"
  echo -e "${CYAN}###############################${NC}"
}

# --- Environment Setup ---
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
  log_success "ModSecurity already cloned and built."
fi

# === Step 3: Clone ModSecurity-nginx Connector ===
print_step "Step 3: Cloning ModSecurity-nginx connector..."
if [ ! -d "$MODSEC_DIR/ModSecurity-nginx" ]; then
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git "$MODSEC_DIR/ModSecurity-nginx"
else
  log_success "ModSecurity-nginx connector already exists."
fi

# === Step 4: Download and Extract NGINX Source ===
print_step "Step 4: Downloading NGINX source..."
cd "$MODSEC_DIR"
NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9.]*')
NGINX_TARBALL="nginx-$NGINX_VERSION.tar.gz"
NGINX_TARBALL_URL="http://nginx.org/download/$NGINX_TARBALL"

if ! wget --spider "$NGINX_TARBALL_URL" 2>/dev/null; then
  log_warn "NGINX version $NGINX_VERSION source may not be available at nginx.org."
fi

if [ ! -f "$NGINX_TARBALL" ]; then
  wget "$NGINX_TARBALL_URL" -O "$NGINX_TARBALL"
fi

if [ ! -d "nginx-$NGINX_VERSION" ]; then
  tar -xvzf "$NGINX_TARBALL"
fi

# === Step 5: Build the NGINX ModSecurity Dynamic Module ===
print_step "Step 5: Building ModSecurity dynamic module for NGINX..."
cd "$MODSEC_DIR/nginx-$NGINX_VERSION"
./configure --with-compat --add-dynamic-module=../ModSecurity-nginx
make modules

# === Step 6: Install ModSecurity NGINX Module ===
print_step "Step 6: Copying built ModSecurity module..."
FOUND_MODSEC_MODULE=$(find "$MODSEC_DIR/nginx-$NGINX_VERSION/objs" -type f -name "ngx_http_modsecurity_module.so" | head -n 1)
if [ -z "$FOUND_MODSEC_MODULE" ]; then
  log_error "Could not find compiled ngx_http_modsecurity_module.so"
fi
sudo mkdir -p "$NGINX_MODULES_DIR"
sudo cp "$FOUND_MODSEC_MODULE" "$NGINX_MODULES_DIR/"
MODSEC_MODULE_PATH="$NGINX_MODULES_DIR/$(basename "$FOUND_MODSEC_MODULE")"
log_success "Module installed at: $MODSEC_MODULE_PATH"

# === Step 6.1: Update nginx.conf to Load Module ===
print_step "Step 6.1: Updating nginx.conf to load module..."
sudo cp "$NGINX_CONF" "$NGINX_CONF.bak"
MODSEC_MODULE_LINE="load_module \"$MODSEC_MODULE_PATH\";"
sudo sed -i '/^[^#]*load_module\s\+["'\'']\?.*ngx_http_modsecurity_module\.so["'\'']\?;/d' "$NGINX_CONF"
sudo sed -i "1i$MODSEC_MODULE_LINE" "$NGINX_CONF"
log_success "nginx.conf updated and backed up."

# === Step 7: Unicode Mapping ===
print_step "Step 7: Copying unicode.mapping..."
sudo mkdir -p "$(dirname "$UNICODE_MAP_DEST")"
if [ -f "$MODSEC_DIR/unicode.mapping" ]; then
  sudo cp "$MODSEC_DIR/unicode.mapping" "$UNICODE_MAP_DEST"
  log_success "unicode.mapping copied to $UNICODE_MAP_DEST"
else
  log_error "unicode.mapping file not found in $MODSEC_DIR"
fi

# === Step 8: Configure ModSecurity ===
print_step "Step 8: Configuring ModSecurity..."
if [ ! -f "$MODSEC_CONF" ]; then
  cp "$MODSEC_DIR/modsecurity.conf-recommended" "$MODSEC_CONF"
  sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$MODSEC_CONF"
fi
log_success "ModSecurity config prepared."

# === Step 9: Create Custom Rules ===
print_step "Step 9: Creating custom ModSecurity rules..."
mkdir -p "$RULES_DIR"
cat <<EOF > "$RULES_DIR/main.conf"
Include $MODSEC_CONF

# Custom Rules
SecRule ARGS:blogtest "@contains test" "id:1111,deny,status:403"
SecRule REQUEST_URI "@beginsWith /admin" "phase:2,t:lowercase,id:2222,deny,msg:'block admin'"
EOF
log_success "Custom rules written to $RULES_DIR/main.conf"

# === Step 10: Setup OWASP CRS ===
print_step "Step 10: Installing OWASP Core Rule Set v$OWASP_CRS_VERSION..."
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
log_success "OWASP CRS included in main.conf"

# === Step 11: Reload NGINX ===
print_step "Step 11: Validating and restarting NGINX..."
if sudo nginx -t; then
  if command -v systemctl &>/dev/null; then
    sudo systemctl restart nginx
  else
    sudo nginx -s reload || sudo nginx
  fi
  log_success "NGINX reloaded with ModSecurity module."
else
  log_error "NGINX configuration test failed!"
fi

# === Final Output ===
SCRIPT_END_TIME=$(date +%s)
TOTAL_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

echo
echo "#######################################################"
log_success "ModSecurity with OWASP CRS installed and configured!"
echo
log_info "Rules applied from: $RULES_DIR/main.conf"
echo
log_info "Script completed in $TOTAL_TIME seconds."
echo "#######################################################"
echo
log_warn "Make sure to add these 2 lines inside the nginx server block (e.g., in default.conf):"
echo
echo "    modsecurity on;"
echo "    modsecurity_rules_file /home/ubuntu/ModSecurity/rules/main.conf;"
echo
echo "#######################################################"
