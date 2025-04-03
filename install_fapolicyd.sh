#!/bin/bash
# Simple fapolicyd installation script

# Exit script on error
set -e

# Change visudo editor
if command -v update-alternatives &> /dev/null; then
    if update-alternatives --list editor | grep -q "vim.basic"; then
        sudo update-alternatives --set editor /usr/bin/vim.basic
    elif update-alternatives --list editor | grep -q "vim.tiny"; then
        sudo update-alternatives --set editor /usr/bin/vim.tiny
    elif update-alternatives --list editor | grep -q "vim"; then
        VIM_PATH=$(update-alternatives --list editor | grep vim | head -1)
        sudo update-alternatives --set editor "$VIM_PATH"
    else
        echo "Error: vim is not installed."
    fi
    echo "vim is set as the default editor."
fi

echo "===== Starting fapolicyd simple installation ====="

# Check current directory
CURRENT_DIR="./src"
DEB_FILE="${CURRENT_DIR}/fapolicyd_1.3.5-1_amd64.deb"
SAMPLE_RULES="${CURRENT_DIR}/sample-rules"

# Check if DEB file exists
if [ ! -f "$DEB_FILE" ]; then
    echo "Error: $DEB_FILE file does not exist."
    exit 1
fi

# Install package
echo "[1/4] Installing fapolicyd package..."
sudo dpkg -i "$DEB_FILE" || {
    echo "Resolving dependency issues..."
    sudo apt-get install -f -y
    sudo dpkg -i "$DEB_FILE"
}

# Create configuration directory
echo "[2/4] Creating configuration directory..."
sudo mkdir -p /etc/fapolicyd/rules.d

# Update configuration file
echo "[3/4] Updating fapolicyd.conf configuration file..."
if [ -f "/etc/fapolicyd/fapolicyd.conf" ]; then
    # Modify existing configuration file
    sudo sed -i 's/^permissive = .*/permissive = 1/' /etc/fapolicyd/fapolicyd.conf
    sudo sed -i 's/^db_max_size = .*/db_max_size = 500/' /etc/fapolicyd/fapolicyd.conf
    sudo sed -i 's/^trust = .*/trust = debdb,file/' /etc/fapolicyd/fapolicyd.conf
    sudo sed -i 's/^integrity = .*/integrity = sha256/' /etc/fapolicyd/fapolicyd.conf
else
    echo "Warning: fapolicyd.conf file does not exist."
fi

# Copy rules files
echo "[4/4] Copying rule files..."
if [ -d "$SAMPLE_RULES" ]; then
    sudo cp "${SAMPLE_RULES}"/*.rules /etc/fapolicyd/rules.d/ 2>/dev/null || true
else
    echo "Warning: sample-rules directory does not exist."
    echo "Attempting to copy rule files from default location..."
    sudo cp /usr/share/fapolicyd/sample-rules/*.rules /etc/fapolicyd/rules.d/ 2>/dev/null || echo "Warning: Could not find rule files."
fi

# Update Python and dynamic linker paths
echo "Updating Python and dynamic linker paths..."
# Update Python2 path
PYTHON2_PATH=$(which python2 2>/dev/null || echo "/usr/bin/python2")
sudo sed -i "s|%python2_path%|${PYTHON2_PATH}|g" /etc/fapolicyd/rules.d/*.rules 2>/dev/null || true

# Update Python3 path
PYTHON3_PATH=$(which python3 2>/dev/null || echo "/usr/bin/python3")
sudo sed -i "s|%python3_path%|${PYTHON3_PATH}|g" /etc/fapolicyd/rules.d/*.rules 2>/dev/null || true

# Update dynamic linker path
if command -v readelf >/dev/null 2>&1; then
  INTERPRETER=$(readelf -e /usr/bin/bash 2>/dev/null | grep "interpreter" | sed -e 's/.*interpreter: \(.*\)/\1/' || echo "/lib64/ld-linux-x86-64.so.2")
else
  INTERPRETER="/lib64/ld-linux-x86-64.so.2"
fi
sudo sed -i "s|%ld_so_path%|${INTERPRETER}|g" /etc/fapolicyd/rules.d/*.rules 2>/dev/null || true

# Start service
echo "Starting fapolicyd service..."
sudo systemctl daemon-reload
sudo systemctl enable fapolicyd
sudo systemctl start fapolicyd || echo "Service start failed. Check status."

echo "===== fapolicyd installation complete ====="
echo ""
echo "Important: Please verify the following after installation."
echo "1. Check service status: sudo systemctl status fapolicyd"
echo "2. Check permissive mode settings:"
echo "   - Current setting is permissive = 1 (monitoring mode)"
echo "   - To enable enforcement, use the following commands:"
echo "     sudo sed -i 's/^permissive = 1/permissive = 0/' /etc/fapolicyd/fapolicyd.conf"
echo "     sudo systemctl restart fapolicyd"
echo ""
echo "Caution: Before enabling enforcement mode (permissive = 0), thorough testing is required."
echo "         Review logs in monitoring mode to identify false positives: journalctl -u fapolicyd"
