#!/bin/bash
set -e

# Talos Linux VPS Installation Script
# This script overwrites the current OS with Talos Linux
# USE WITH CAUTION - this will destroy all data on the target disk

# Configuration - modify these before running
TALOS_IMAGE_URL="${TALOS_IMAGE_URL:-}"
TARGET_DISK="${TARGET_DISK:-/dev/sda}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Talos Linux VPS Installation Script ===${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check for image URL
if [[ -z "$TALOS_IMAGE_URL" ]]; then
    echo -e "${RED}Error: TALOS_IMAGE_URL environment variable not set${NC}"
    echo ""
    echo "Usage:"
    echo "  export TALOS_IMAGE_URL='https://factory.talos.dev/image/<schematic>/<version>/metal-amd64.raw.gz'"
    echo "  ./talos-vps-install.sh"
    echo ""
    echo "Get your image URL from https://factory.talos.dev"
    echo "IMPORTANT: Use 'metal' or 'nocloud' variant, NOT 'cloudstack' or other cloud-specific images"
    exit 1
fi

# Confirm target disk
echo -e "${YELLOW}Target disk: ${TARGET_DISK}${NC}"
echo ""
lsblk "$TARGET_DISK"
echo ""
echo -e "${RED}WARNING: This will COMPLETELY ERASE ${TARGET_DISK}${NC}"
echo -e "${RED}The system will reboot into Talos Linux after completion${NC}"
echo ""
read -p "Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${GREEN}[1/5] Installing dependencies...${NC}"
apt update && apt install -y busybox-static wget

echo ""
echo -e "${GREEN}[2/5] Setting up tmpfs environment...${NC}"
mkdir -p /tmp/tmproot
mount -t tmpfs -o size=2G tmpfs /tmp/tmproot
mkdir -p /tmp/tmproot/{bin,tmp}
cp /bin/busybox /tmp/tmproot/bin/
ln -sf busybox /tmp/tmproot/bin/gunzip
ln -sf busybox /tmp/tmproot/bin/dd
ln -sf busybox /tmp/tmproot/bin/sync
ln -sf busybox /tmp/tmproot/bin/reboot

echo ""
echo -e "${GREEN}[3/5] Downloading Talos image...${NC}"
wget -O /tmp/tmproot/tmp/talos.raw.gz "$TALOS_IMAGE_URL"

echo ""
echo -e "${GREEN}[4/5] Writing image to disk...${NC}"
echo "This may take a few minutes..."
/tmp/tmproot/bin/gunzip -c /tmp/tmproot/tmp/talos.raw.gz | /tmp/tmproot/bin/dd of="$TARGET_DISK" bs=4M

echo ""
echo -e "${GREEN}[5/5] Syncing and rebooting...${NC}"
/tmp/tmproot/bin/sync
sleep 2

echo ""
echo -e "${GREEN}Installation complete. Rebooting into Talos Linux...${NC}"
echo -e "${YELLOW}After reboot, apply your config with:${NC}"
echo "  talosctl apply-config --insecure --nodes <VPS-IP> --file controlplane.yaml"
sleep 3

/tmp/tmproot/bin/reboot -f
