#!/bin/bash
#
# Ghostwave — WPA2 handshake capture helper
#
# Automates the monitor-mode setup + broad scan steps from the README.
# Run on your own network only, with explicit permission.
#
# Usage: sudo ./capture.sh

set -e

# --- Config: change this to your wireless interface name ---
# Find yours with: iw dev
INTERFACE="wlp2s0"

echo "👻 Ghostwave — setup starting"

# 1. Check root
if [ "$EUID" -ne 0 ]; then
  echo "This script needs root. Run with: sudo ./capture.sh"
  exit 1
fi

# 2. Stop services that interfere with monitor mode
echo "[1/5] Stopping NetworkManager / wpa_supplicant..."
airmon-ng check kill

# 3. Clear any RF-kill blocks
echo "[2/5] Checking RF-kill status..."
rfkill unblock all
rfkill list

# 4. Enable monitor mode
echo "[3/5] Enabling monitor mode on $INTERFACE..."
ip link set "$INTERFACE" down
iw "$INTERFACE" set monitor none
ip link set "$INTERFACE" up

# 5. Confirm monitor mode is active
echo "[4/5] Confirming interface mode..."
iw dev

echo "[5/5] Monitor mode should now be active on $INTERFACE."
echo ""
echo "Next steps (manual, not automated — see README):"
echo "  1. Run: airodump-ng $INTERFACE"
echo "     → find your target's BSSID and channel"
echo "  2. Run: airodump-ng -c CHANNEL --bssid BSSID -w capture $INTERFACE"
echo "     → wait for 'WPA handshake' to appear"
echo "  3. Crack it: aircrack-ng -w ~/rockyou.txt capture-01.cap"
echo ""
echo "To restore normal Wi-Fi afterward, run:"
echo "  sudo systemctl start NetworkManager"
