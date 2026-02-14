#!/bin/bash
#
# Installer for MateBook Touchpad Resume Fix
# Installs, enables, and immediately runs the fix
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "MateBook Touchpad Resume Fix Installer"
echo "======================================="
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (sudo)${NC}"
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install the fix script
echo "Installing touchpad-fix-resume.sh to /usr/local/bin/..."
cp "$SCRIPT_DIR/touchpad-fix-resume.sh" /usr/local/bin/
chmod 755 /usr/local/bin/touchpad-fix-resume.sh

# Install the systemd service
echo "Installing systemd service..."
cp "$SCRIPT_DIR/touchpad-fix-resume.service" /etc/systemd/system/
chmod 644 /etc/systemd/system/touchpad-fix-resume.service

# Reload systemd and enable the service
echo "Enabling service..."
systemctl daemon-reload
systemctl enable touchpad-fix-resume.service

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""

# Run the fix immediately
echo "Running touchpad fix now..."
echo ""
/usr/local/bin/touchpad-fix-resume.sh

echo ""
echo "---"
echo "Logs:    journalctl -t touchpad-fix"
echo "Status:  systemctl status touchpad-fix-resume.service"
echo ""
