#!/usr/bin/env bash

# ==============================================================================
# 🛡️ AUTOMATED MODSECURITY & OWASP CRS INSTALLER FOR NGINX
# ==============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Color & Logging Definitions ---
readonly NC='\033[0m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

log_step() {
  echo -e "\n${CYAN}=======================================================${NC}"
  echo -e "🕒 $(date '+%Y-%m-%d %H:%M:%S') | $1"
  echo -e "${CYAN}=======================================================${NC}"
}

# Enforce root execution
if [ "$EUID" -ne 0 ]; then
  log_error "This script must be run as root."
  exit 1
fi

# Fix #5: Anchor paths explicitly to the script's actual directory
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODSEC_DIR="$WORK_DIR/ModSecurity"
RULES_DIR="$MODSEC_DIR/rules"
NGINX_BUILD_DIR="$MODSEC_DIR/nginx_src"
NGINX_MODULES_DIR="/etc/nginx/modules"
NGINX_MODULES_ENABLED_DIR="/etc/nginx/modules-enabled"
NGINX_CONF="/etc/nginx/nginx.conf"
MODSEC_CONF="$MODSEC_DIR/modsecurity.conf"
OWASP_CRS_VERSION="4.3.0"
UNICODE_MAP_DEST="/etc/nginx/modsec/unicode.mapping"
SWAP_PATH="/ephemeral_compiler_swap"

SCRIPT_START_TIME=$(date +%s)

cleanup() {
  local exit_code=$?

  # Fix #2: Move rm -f outside the grep conditional so orphaned swap files are always purged
  if [ -f "$SWAP_PATH" ]; then
    if grep -q "$SWAP_PATH" /proc/swaps 2>/dev/null; then
      log_warn "Disabling temporary compiler swap space..."
      swapoff "$SWAP_PATH" 2>/dev/null || true
    fi
    log_warn "Removing ephemeral swap file..."
    rm -f "$SWAP_PATH" 2>/dev/null || true
  fi

  rm -rf "$NGINX_BUILD_DIR" 2>/dev/null || true
  if [ "$exit_code" -ne 0 ]; then
    log_error "Execution failed at line $LINENO."
  fi
  exit "$exit_code"
}
trap cleanup EXIT ERR

# Step 1: Install Required Dependencies
log_step "Step 1: Installing required packages..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  nginx build-essential autoconf automake libtool pkg-config git wget dpkg-dev \
  zlib1g-dev libpcre3-dev libxml2-dev libcurl4-openssl-dev liblua5.3-dev \
  libpcre2-dev libssl-dev libxslt1-dev libgd-dev libgeoip-dev libperl-dev libmaxminddb-dev
log_success "Dependencies installed."

# Step 2: Clone and Build ModSecurity Core Engine
log_step "Step 2: Cloning and building ModSecurity Core..."
if [ ! -f "/usr/local/lib/libmodsecurity.so" ]; then
  log_info "Cloning ModSecurity repository with submodules into $MODSEC_DIR..."
  rm -rf "$MODSEC_DIR"
  git clone --depth 1 --recurse-submodules -b v3.0.15 --single-branch https://github.com/SpiderLabs/ModSecurity "$MODSEC_DIR"

  # Fix #1: Check disk space first before attempting dd allocation
  if [ $(free -m | awk '/Mem:/ {print $2}') -lt 4000 ]; then
    FREE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$FREE_SPACE" -lt 4500 ]; then
      log_error "Insufficient disk space to create swap file ($FREE_SPACE MB available, >4500 MB required)."
      exit 1
    fi

    log_warn "System RAM is under 4GB; provisioning temporary 4GB swap space..."
    dd if=/dev/zero of="$SWAP_PATH" bs=1M count=4096 status=none
    chmod 600 "$SWAP_PATH"
    mkswap "$SWAP_PATH" >/dev/null
    swapon "$SWAP_PATH"
  fi

  cd "$MODSEC_DIR"
  log_info "Running build.sh and configure scripts..."
  ./build.sh
  ./configure --prefix=/usr/local
  log_info "Compiling ModSecurity Core Engine..."
  make -j"$(nproc)"
  make install
  ldconfig
  log_success "ModSecurity Core Engine built and installed to /usr/local/lib."

  if [ -f "$SWAP_PATH" ]; then
    swapoff "$SWAP_PATH" || true
    rm -f "$SWAP_PATH" || true
  fi
else
  log_success "ModSecurity core library already exists in /usr/local/lib."
fi

# Step 3: Clone ModSecurity-nginx Connector
log_step "Step 3: Cloning ModSecurity-nginx connector..."
if [ ! -d "$MODSEC_DIR/ModSecurity-nginx" ]; then
  git clone --depth 1 -b v1.0.4 --single-branch https://github.com/SpiderLabs/ModSecurity-nginx.git "$MODSEC_DIR/ModSecurity-nginx"
  log_success "Connector cloned to $MODSEC_DIR/ModSecurity-nginx."
else
  log_info "ModSecurity-nginx connector source already exists."
fi

# Step 4: Download Matching NGINX Source Inside ModSecurity Folder
log_step "Step 4: Fetching active NGINX source package..."
mkdir -p "$NGINX_BUILD_DIR"
cd "$NGINX_BUILD_DIR"

NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9.]*')
log_info "Detected running NGINX version: $NGINX_VERSION"

NGINX_TARBALL="nginx-$NGINX_VERSION.tar.gz"
NGINX_URL="https://nginx.org/download/$NGINX_TARBALL"

wget -q "$NGINX_URL" -O "$NGINX_TARBALL"
tar -xzf "$NGINX_TARBALL"
cd "nginx-$NGINX_VERSION"
log_success "NGINX source extracted in $NGINX_BUILD_DIR."

# Step 5: Build NGINX ModSecurity Dynamic Module with Correct ABI Flags
log_step "Step 5: Building NGINX ModSecurity module matching active binary flags..."
RAW_ARGS=$(nginx -V 2>&1 | grep "configure arguments:" | sed 's/configure arguments://')

CLEAN_ARGS=$(echo "$RAW_ARGS" | sed "s/--with-cc-opt='/--with-cc-opt='-I\/usr\/local\/include /g" | sed "s/--with-ld-opt='/--with-ld-opt='-L\/usr\/local\/lib -Wl,-rpath,\/usr\/local\/lib /g")

eval "./configure $CLEAN_ARGS --with-compat --add-dynamic-module=$MODSEC_DIR/ModSecurity-nginx" >/dev/null
make modules -j"$(nproc)"
log_success "Dynamic module compiled successfully."

# Step 6: Deploy compiled module binary
log_step "Step 6: Deploying compiled dynamic module..."
COMPILED_SO="$NGINX_BUILD_DIR/nginx-$NGINX_VERSION/objs/ngx_http_modsecurity_module.so"

mkdir -p "$NGINX_MODULES_DIR"
cp "$COMPILED_SO" "$NGINX_MODULES_DIR/"
chmod 644 "$NGINX_MODULES_DIR/ngx_http_modsecurity_module.so"
log_success "Copied module to $NGINX_MODULES_DIR/ngx_http_modsecurity_module.so."

# Step 7: Use modules-enabled Standard Configuration
log_step "Step 7: Enabling module via /etc/nginx/modules-enabled standard..."
mkdir -p "$NGINX_MODULES_ENABLED_DIR"
echo 'load_module "/etc/nginx/modules/ngx_http_modsecurity_module.so";' > "$NGINX_MODULES_ENABLED_DIR/50-modsecurity.conf"
chmod 644 "$NGINX_MODULES_ENABLED_DIR/50-modsecurity.conf"

# Ensure nginx.conf includes modules-enabled at top-level
if ! grep -q "include /etc/nginx/modules-enabled/\*\.conf;" "$NGINX_CONF"; then
  log_info "Adding modules-enabled include to $NGINX_CONF..."
  sed -i '1iinclude /etc/nginx/modules-enabled/*.conf;' "$NGINX_CONF"
fi

log_success "Enabled module directive in $NGINX_MODULES_ENABLED_DIR/50-modsecurity.conf and updated $NGINX_CONF."

# Step 8: Unicode Mapping
log_step "Step 8: Deploying unicode.mapping tracking configuration..."
mkdir -p "/etc/nginx/modsec"
if [ -f "$MODSEC_DIR/unicode.mapping" ]; then
  cp "$MODSEC_DIR/unicode.mapping" "$UNICODE_MAP_DEST"
  chmod 644 "$UNICODE_MAP_DEST"
  log_success "unicode.mapping copied to $UNICODE_MAP_DEST."
fi

# Step 9: Configure ModSecurity
log_step "Step 9: Preparing ModSecurity configuration..."
if [ ! -f "$MODSEC_CONF" ]; then
  cp "$MODSEC_DIR/modsecurity.conf-recommended" "$MODSEC_CONF"
  sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$MODSEC_CONF"
  chmod 644 "$MODSEC_CONF"
  log_info "Created $MODSEC_CONF with SecRuleEngine On."
else
  log_info "$MODSEC_CONF already exists. Skipping initialization."
fi

# Step 10: Setup ModSecurity Rules in ModSecurity/rules
log_step "Step 10: Creating custom rules and fetching OWASP CRS..."
mkdir -p "$RULES_DIR"

# Fix #3: Protect existing main.conf from being overwritten on re-runs
if [ ! -f "$RULES_DIR/main.conf" ]; then
  log_info "Creating default $RULES_DIR/main.conf..."
  cat <<EOF > "$RULES_DIR/main.conf"
Include $MODSEC_CONF

# Custom Rules
SecRule ARGS:blogtest "@contains test" "id:1111,deny,status:403"
SecRule REQUEST_URI "@beginsWith /admin" "phase:2,t:lowercase,id:2222,deny,msg:'block admin'"
EOF
else
  log_info "Existing $RULES_DIR/main.conf detected. Preserving existing configuration."
fi

cd "$RULES_DIR"
if [ ! -d "owasp-crs" ]; then
  log_info "Cloning OWASP CRS v$OWASP_CRS_VERSION into $RULES_DIR/owasp-crs..."
  git clone --depth 1 -b "v$OWASP_CRS_VERSION" https://github.com/coreruleset/coreruleset.git owasp-crs
  if [ -f "owasp-crs/crs-setup.conf.example" ]; then
    cp owasp-crs/crs-setup.conf.example owasp-crs/crs-setup.conf
  fi
fi

if ! grep -q "owasp-crs/crs-setup.conf" "$RULES_DIR/main.conf"; then
  cat <<EOF >> "$RULES_DIR/main.conf"

# OWASP CRS Directives
Include $RULES_DIR/owasp-crs/crs-setup.conf
Include $RULES_DIR/owasp-crs/rules/*.conf
EOF
fi

chmod 644 "$RULES_DIR/main.conf"
log_success "Rule configuration ready at $RULES_DIR/main.conf."

# Step 11: Validate and Reload NGINX
log_step "Step 11: Validating NGINX configuration and reloading..."
if nginx -t; then
  systemctl reload nginx || systemctl restart nginx
  log_success "NGINX reloaded successfully with ModSecurity module!"
else
  log_error "NGINX configuration test failed!"
  exit 1
fi

TOTAL_TIME=$(($(date +%s) - SCRIPT_START_TIME))
echo -e "\n======================================================="
log_success "INSTALLATION COMPLETED SUCCESSFULLY in $TOTAL_TIME seconds."
log_info "ModSecurity Folder : $MODSEC_DIR"
log_info "Rules File         : $RULES_DIR/main.conf"
log_warn "Add the following lines inside your NGINX server block:"
echo -e "   ${CYAN}modsecurity on;${NC}"
echo -e "   ${CYAN}modsecurity_rules_file $RULES_DIR/main.conf;${NC}"
echo "======================================================="
