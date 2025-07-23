#!/bin/bash
# Auto install Netdata for Debian & Raspberry Pi
# Works on Debian 10/11/12 & Raspberry Pi OS (32/64-bit)

set -e

echo "[+] Updating system..."
sudo apt update && sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y curl lsb-release sudo

echo "[+] Detecting system architecture..."
ARCH=$(uname -m)
echo "[+] Detected: $ARCH"

# Install Netdata
echo "[+] Installing Netdata..."
bash <(curl -Ss https://my-netdata.io/kickstart.sh) --stable-channel --disable-telemetry

# Enable and start Netdata
echo "[+] Enabling Netdata service..."
sudo systemctl enable netdata
sudo systemctl start netdata

IP_ADDR=$(hostname -I | awk '{print $1}')

echo ""
echo "[+] Netdata installed successfully!"
echo ">>> Web GUI Access http://$IP_ADDR:19999"
echo ""
