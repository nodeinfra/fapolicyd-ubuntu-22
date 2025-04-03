#!/bin/bash
# fapolicyd installation and configuration script
# Based on GitHub Actions workflow for Ubuntu 22.04 (Jammy)

# Terminate script on error
set -e

echo "===== Starting fapolicyd installation and configuration ====="

# Update package list
echo "[1/8] Updating package list"
sudo apt update

# Install dependencies in two groups (like in GitHub Actions)
echo "[2/8] Installing dependencies - group 1"
sudo apt install -y autoconf automake libtool gcc libdpkg-dev libmd-dev uthash-dev liblmdb-dev libudev-dev

echo "[3/8] Installing dependencies - group 2"
sudo apt install -y libgcrypt20-dev libssl-dev libmagic-dev libcap-ng-dev libseccomp-dev make debmake debhelper python3-dev file libsystemd-dev linux-headers-$(uname -r) librpm-dev

# Set working directory
echo "[4/8] Setting up working directory"
cd /tmp
rm -rf fapolicyd 2>/dev/null || true

# Download source code
echo "[5/8] Cloning source code from GitHub"
git clone https://github.com/linux-application-whitelisting/fapolicyd.git
cd fapolicyd

# Generate config files
echo "[6/8] Generating configuration files"
./autogen.sh

# Configure
echo "[7/8] Configuring build environment"
./configure --without-rpm --with-audit --disable-shared --disable-dependency-tracking --with-deb

# Fix placeholders in rules files
echo "[7.5/8] Fixing rules placeholders"
# Fix Python2 path
PYTHON2_PATH=$(which python2 2>/dev/null || echo "/usr/bin/python2")
sed -i "s|%python2_path%|${PYTHON2_PATH}|g" rules.d/*.rules

# Fix Python3 path
PYTHON3_PATH=$(which python3 2>/dev/null || echo "/usr/bin/python3")
sed -i "s|%python3_path%|${PYTHON3_PATH}|g" rules.d/*.rules

# Fix dynamic linker path
if command -v readelf >/dev/null 2>&1; then
  INTERPRETER=$(readelf -e /usr/bin/bash 2>/dev/null | grep "interpreter" | sed -e 's/.*interpreter: \(.*\)/\1/' || echo "/lib64/ld-linux-x86-64.so.2")
else
  INTERPRETER="/lib64/ld-linux-x86-64.so.2"
fi
sed -i "s|%ld_so_path%|${INTERPRETER}|g" rules.d/*.rules

# Build and create package
echo "[8/8] Building source code and creating package"
make
make dist
cd deb
./build_deb.sh

# Install the Debian package
echo "Installing the built Debian package"
sudo dpkg -i fapolicyd_*.deb || {
  echo "Package installation failed, attempting to fix dependencies"
  sudo apt-get install -f -y
  sudo dpkg -i fapolicyd_*.deb
}

# Update specific configuration values in fapolicyd.conf
echo "Updating fapolicyd configuration values"
if [ -f "/etc/fapolicyd/fapolicyd.conf" ]; then
  # Update permissive mode
  sudo sed -i 's/^permissive = .*/permissive = 1/' /etc/fapolicyd/fapolicyd.conf
  
  # Update trust value (even though it might already be set to "file")
  sudo sed -i 's/^trust = .*/trust = debdb,file/' /etc/fapolicyd/fapolicyd.conf
  
  # Update integrity value
  sudo sed -i 's/^integrity = .*/integrity = sha256/' /etc/fapolicyd/fapolicyd.conf
  
  echo "Updated configuration values in existing fapolicyd.conf file"
else
  echo "Warning: /etc/fapolicyd/fapolicyd.conf not found. Creating new file."
  cat << 'EOF' | sudo tee /etc/fapolicyd/fapolicyd.conf > /dev/null
#
# fapolicyd configuration file
# For detailed explanation, see man fapolicyd.conf
#

permissive = 1
trust = debdb,file
integrity = sha256

# Other default values
nice_val = 14
q_size = 800
uid = fapolicyd
gid = fapolicyd
do_stat_report = 1
detailed_report = 1
db_max_size = 100
subj_cache_size = 1549
obj_cache_size = 8191
watch_fs = ext2,ext3,ext4,tmpfs,xfs,vfat,iso9660,btrfs
syslog_format = rule,dec,perm,auid,pid,exe,:,path,ftype,trust
rpm_sha256_only = 0
allow_filesystem_mark = 0
report_interval = 0
EOF
fi

# Setting up fapolicyd rules (known-libs configuration)
echo "Setting up fapolicyd rules (known-libs configuration)..."
sudo mkdir -p /etc/fapolicyd/rules.d

# known-libs 설정 파일 복사
sudo cp /usr/share/fapolicyd/sample-rules/10-languages.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/20-dracut.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/21-updaters.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/30-patterns.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/40-bad-elf.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/41-shared-obj.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/42-trusted-elf.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/70-trusted-lang.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/72-shell.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/90-deny-execute.rules /etc/fapolicyd/rules.d/
sudo cp /usr/share/fapolicyd/sample-rules/95-allow-open.rules /etc/fapolicyd/rules.d/

# Ensure the fapolicyd service is properly set up
if [ -f "/etc/systemd/system/fapolicyd.service" ] || [ -f "/lib/systemd/system/fapolicyd.service" ]; then
  echo "Starting fapolicyd service"
  sudo systemctl daemon-reload
  sudo systemctl enable fapolicyd
  sudo systemctl start fapolicyd
  
  # Update database
  if command -v fapolicyd-cli &> /dev/null; then
    echo "Updating fapolicyd database"
    sudo fapolicyd-cli -ur 2>/dev/null || echo "Warning: fapolicyd-cli command failed, please run it manually later"
    echo "Restarting fapolicyd service..."
    sudo systemctl restart fapolicyd
  fi
else
  echo "Warning: fapolicyd.service not found. Service might not be properly installed."
fi

echo "===== fapolicyd installation and configuration completed ====="
echo "Check status: sudo systemctl status fapolicyd"
