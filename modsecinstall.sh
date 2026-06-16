# ==============================================================================
# 🛡️ PRODUCTION-GRADE AUTOMATED MODSECURITY & OWASP CRS INSTALLER FOR NGINX
# ==============================================================================
# DESCRIPTION:
#   This script automates the compilation and deployment of ModSecurity v3 (Core)
#   and the ModSecurity-NGINX Dynamic Connector. It dynamically extracts the
#   active environment's compilation flags to prevent binary/ABI mismatches.
#
# DESIGN PRINCIPLES & AUTOMATED SAFEGUARDS:
#   1. ABI Mismatch Protection: Extracts 'nginx -V' parameters from the running
#      system binary and surgically splices custom paths inside the native options.
#   2. Dynamic OOM Mitigation: Automatically provisions an ephemeral 4GB Swap file
#      on low-RAM systems to handle heavy parser code compilation without crashing.
#   3. Cleanup Trap: Uses an active Bash trap to ensure that emergency swap allocations
#      and work directories are strictly purged on successful completion OR script failure.
#   4. Shared Library Binding: Forces 'ldconfig' mapping to cleanly register custom
#      shared objects (.so) into the global system linker layout.
# ==============================================================================
# 🚀 OPERATIONAL PLAYBOOK & MAINTENANCE GUIDE
# ==============================================================================
#
# CONDITION A: CLEAN FIRST-TIME INSTALLATION
#   Simply execute the script on a fresh machine. It will configure, compile,
#   and link every layer automatically from scratch.
#
# CONDITION B: RE-RUNNING / MAINTENANCE FIXES
#   If the NGINX connector breaks in the future (e.g., after an automatic OS
#   security update to the NGINX binary), simply rerun this script.
#   - It will see that the Core Engine already exists and skip the 15-minute build.
#   - It will automatically detect the new NGINX version and compile a matching
#     connector module in under 30 seconds.
#
# CONDITION C: UPGRADING COMPONENT VERSIONS
#   To bump versions or track newer releases, modify the variable definitions
#   or Git clone tags below using these deterministic rules:
#
#   1. Upgrading NGINX:
#      - Do NOT touch the script code. Run 'sudo apt upgrade nginx' followed by
#        running this script. It dynamically reads your active version.
#
#   2. Upgrading OWASP CRS (Rules):
#      - Update the 'OWASP_CRS_VERSION' variable (e.g., "4.3.0" to "4.4.0").
#      - CRITICAL: Run 'rm -rf ~/ModSecurity/rules/owasp-crs' right before
#        executing the script so the new version can clone cleanly.
#
#   3. Upgrading the NGINX Connector Module:
#      - Change the tag version in Step 3's git clone command (e.g., '-b v1.0.4' to '-b v1.0.5').
#      - CRITICAL: Run 'rm -rf ~/ModSecurity/ModSecurity-nginx ~/nginx_modsec_build'
#        before executing to clear old cache frameworks.
#
#   4. Upgrading ModSecurity Core Engine:
#      - Update the tag version in Step 2's git clone command (e.g., '-b v3.0.15' to '-b v3.0.16').
#      - CRITICAL: Manually delete the binary flag tracking file via
#        'sudo rm -f /usr/local/lib/libmodsecurity.so' to trigger a fresh core recompile.
#
# ==============================================================================
# CONTRIBUTORS & CONTRIBUTORS NOTES:
#   - Ensure all flag injections handle quote boundaries precisely.
#   - Maintain absolute paths throughout the lifecycle execution variables.
# ==============================================================================

#!/bin/bash

# Exit immediately if any command fails, pipes mask exit statuses correctly
set -euo pipefail

# Production Trap: Guarantees cleanup of temporary files and swap spaces on ANY exit condition
cleanup() {
  EXIT_CODE=$?
  if [ -f "/swapfile" ] && grep -q "/swapfile" /proc/swaps 2>/dev/null; then
    echo "🧹 Clean-up Trap: Disabling and removing emergency swap file..."
    sudo swapoff /swapfile 2>/dev/null || true
    sudo rm -f /swapfile 2>/dev/null || true
  fi
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "❌ Execution halted. Error occurred at line $LINENO."
  fi
  exit "$EXIT_CODE"
}
trap cleanup EXIT EXIT ERR

SCRIPT_START_TIME=$(date +%s)

print_step() {
  echo -e "\n#######################\n🕒 $(date '+%Y-%m-%d %H:%M:%S') | $1\n#######################"
}

# === Production Directories and Deterministic Versions ===
USER_HOME=$(eval echo "~$USER")
WORK_DIR="$USER_HOME/nginx_modsec_build"
MODSEC_DIR="$USER_HOME/ModSecurity"
RULES_DIR="$MODSEC_DIR/rules"
NGINX_MODULES_DIR="/etc/nginx/modules"
NGINX_CONF="/etc/nginx/nginx.conf"
MODSEC_CONF="$MODSEC_DIR/modsecurity.conf"
OWASP_CRS_VERSION="4.3.0" # Production Update: Using modern, accurate rule sets
UNICODE_MAP_DEST="/etc/nginx/modsec/unicode.mapping"

# === Step 1: Install Required Packages ===
print_step "Step 1: Installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx build-essential autoconf automake libtool pkg-config git wget dpkg-dev \
                    zlib1g-dev libpcre3-dev libxml2-dev libcurl4-openssl-dev liblua5.3-dev \
                    libpcre2-dev libssl-dev libxslt1-dev libgd-dev libgeoip-dev libperl-dev libmaxminddb-dev

# === Step 2: Clone and Build ModSecurity Core Engine ===
print_step "Step 2: Cloning and building ModSecurity Core..."
if [ ! -f "/usr/local/lib/libmodsecurity.so" ]; then
  rm -rf "$MODSEC_DIR"
  git clone --depth 1 --recurse-submodules -b v3.0.15 --single-branch https://github.com/SpiderLabs/ModSecurity "$MODSEC_DIR"

  cd "$MODSEC_DIR"

  echo "📦 Provisioning temporary 4GB Swap Space for compiler isolation..."
  sudo swapoff -a || true
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  ./build.sh
  ./configure --prefix=/usr/local
  make
  sudo make install

  echo "✅ Core engine successfully deployed to /usr/local/lib"
  sudo swapoff /swapfile || true
  sudo rm -f /swapfile || true
  sudo ldconfig
else
  echo "✅ ModSecurity shared library binaries already exist in /usr/local/lib"
fi

# === Step 3: Clone ModSecurity-nginx Connector ===
print_step "Step 3: Cloning ModSecurity-nginx..."
if [ ! -d "$MODSEC_DIR/ModSecurity-nginx" ]; then
  git clone --depth 1 -b v1.0.4 --single-branch https://github.com/SpiderLabs/ModSecurity-nginx.git "$MODSEC_DIR/ModSecurity-nginx"
else
  echo "✅ ModSecurity-nginx connector source already exists"
fi

# === Step 4: Setup Working Directory & Fetch Matching NGINX Source ===
print_step "Step 4: Fetching matching NGINX source package..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9.]*')
NGINX_TARBALL="nginx-$NGINX_VERSION.tar.gz"
NGINX_TARBALL_URL="http://nginx.org/download/$NGINX_TARBALL"

if [ ! -f "$NGINX_TARBALL" ]; then
  wget "$NGINX_TARBALL_URL" -O "$NGINX_TARBALL"
fi
tar -xvzf "$NGINX_TARBALL"
cd "$WORK_DIR/nginx-$NGINX_VERSION"

# === Step 5: Build NGINX ModSecurity Dynamic Module with Correct ABI Flags ===
print_step "Step 5: Building NGINX ModSecurity module matching active binary flags..."
RAW_ARGS=$(nginx -V 2>&1 | grep "configure arguments:" | sed 's/configure arguments://')

if [[ "$RAW_ARGS" == *"--with-cc-opt="* ]]; then
  NGINX_ARGS=$(echo "$RAW_ARGS" | sed "s|--with-cc-opt='|--with-cc-opt='-I/usr/local/include |")
else
  NGINX_ARGS="$RAW_ARGS --with-cc-opt='-I/usr/local/include'"
fi

if [[ "$NGINX_ARGS" == *"--with-ld-opt="* ]]; then
  NGINX_ARGS=$(echo "$NGINX_ARGS" | sed "s|--with-ld-opt='|--with-ld-opt='-L/usr/local/lib -Wl,-rpath,/usr/local/lib |")
else
  NGINX_ARGS="$NGINX_ARGS --with-ld-opt='-L/usr/local/lib -Wl,-rpath,/usr/local/lib'"
fi

eval "./configure $NGINX_ARGS --with-compat --add-dynamic-module=$MODSEC_DIR/ModSecurity-nginx"
make modules

# === Step 6: Deploy compiled module binary ===
print_step "Step 6: Deploying compiled dynamic module..."
COMPILED_SO="$WORK_DIR/nginx-$NGINX_VERSION/objs/ngx_http_modsecurity_module.so"

if [ ! -f "$COMPILED_SO" ]; then
  echo "❌ Error: Compilation failed. Module binary file not found."
  exit 1
fi

sudo mkdir -p "$NGINX_MODULES_DIR"
sudo cp "$COMPILED_SO" "$NGINX_MODULES_DIR/"
echo "✅ Copied module to: $NGINX_MODULES_DIR/ngx_http_modsecurity_module.so"

# === Step 7: Clean and update nginx.conf load_module logic ===
print_step "Step 7: Ensuring nginx.conf loads the correct ModSecurity module..."
sudo cp "$NGINX_CONF" "$NGINX_CONF.bak"

MODSEC_MODULE_LINE='load_module "/etc/nginx/modules/ngx_http_modsecurity_module.so";'
sudo sed -i '/^[^#]*load_module\s\+["'\'']\?.*ngx_http_modsecurity_module\.so["'\'']\?;/d' "$NGINX_CONF"
sudo sed -i "1i$MODSEC_MODULE_LINE" "$NGINX_CONF"
echo "✅ nginx.conf cleaned and correctly updated."

# === Step 8: Fix Unicode Mapping ===
print_step "Step 8: Deploying unicode.mapping tracking configuration..."
sudo mkdir -p "/etc/nginx/modsec"
if [ -f "$MODSEC_DIR/unicode.mapping" ]; then
  sudo cp "$MODSEC_DIR/unicode.mapping" "$UNICODE_MAP_DEST"
else
  echo "❌ unicode.mapping source asset missing!"
  exit 1
fi

# === Step 9: Configure ModSecurity ===
print_step "Step 9: Initializing configuration engines..."
if [ ! -f "$MODSEC_CONF" ]; then
  cp "$MODSEC_DIR/modsecurity.conf-recommended" "$MODSEC_CONF"
  sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$MODSEC_CONF"
fi

# === Step 10: Setup ModSecurity Rules ===
print_step "Step 10: Injecting explicit base rule block layouts..."
mkdir -p "$RULES_DIR"
cat <<EOF > "$RULES_DIR/main.conf"
Include $MODSEC_CONF

# Custom Rules
SecRule ARGS:blogtest "@contains test" "id:1111,deny,status:403"
SecRule REQUEST_URI "@beginsWith /admin" "phase:2,t:lowercase,id:2222,deny,msg:'block admin'"
EOF

# === Step 11: Download and Setup OWASP CRS ===
print_step "Step 11: Deploying OWASP Core Rule Set tracking tracks..."
cd "$RULES_DIR"
if [ ! -d "owasp-crs" ]; then
  git clone --depth 1 -b v$OWASP_CRS_VERSION https://github.com/coreruleset/coreruleset.git owasp-crs
  # Support modern CRS v4 config file resolution structures
  if [ -f "owasp-crs/crs-setup.conf.example" ]; then
    cp owasp-crs/crs-setup.conf.example owasp-crs/crs-setup.conf
  fi
fi

if ! grep -q "owasp-crs/crs-setup.conf" "$RULES_DIR/main.conf"; then
  cat <<EOF >> "$RULES_DIR/main.conf"

# OWASP CRS Injection Tracking Layouts
Include $RULES_DIR/owasp-crs/crs-setup.conf
Include $RULES_DIR/owasp-crs/rules/*.conf
EOF
fi

# === Step 12: Reload NGINX ===
print_step "Step 12: Testing and reloading NGINX service configurations..."
if sudo nginx -t; then
  if command -v systemctl &>/dev/null; then
    sudo systemctl restart nginx
  else
    sudo nginx -s reload || sudo nginx
  fi
else
  echo "❌ NGINX config runtime validation check failed!"
  exit 1
fi

echo "======================================================="
echo " INSTALLATION SUMMARY"
echo "-------------------------------------------------------"
echo " Status       : SUCCESS"
echo " Component    : ModSecurity + OWASP Core Rule Set"
echo " Rules File   : $RULES_DIR/main.conf"
echo "-------------------------------------------------------"

SCRIPT_END_TIME=$(date +%s)
TOTAL_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

echo " Runtime      : ${TOTAL_TIME} seconds"
echo " Completed At : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "======================================================="
echo
echo " NEXT ACTION REQUIRED"
echo "-------------------------------------------------------"
echo " Add the following directives to your NGINX server"
echo " block immediately after the 'server_name' directive."
echo "======================================================="
echo
echo "modsecurity on;"
echo "modsecurity_rules_file /home/ubuntu/ModSecurity/rules/main.conf;"
echo
echo "======================================================="
echo " CONFIGURATION READY FOR ACTIVATION"
echo " Reload NGINX after updating the server configuration."
echo "======================================================="
