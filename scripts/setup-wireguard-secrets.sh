#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}WireGuard Secrets Setup Script${NC}"
echo "================================"
echo ""

# Check for required tools
for cmd in wg op; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed${NC}"
        exit 1
    fi
done

# Check if logged into 1Password
if ! op account get &> /dev/null; then
    echo -e "${YELLOW}Not logged into 1Password. Running 'op signin'...${NC}"
    eval $(op signin)
fi

# Prompt for configuration values
echo -e "${YELLOW}Enter configuration values:${NC}"
echo ""

read -p "WAN Interface name on tortuga (e.g., eth0): " WAN_INTERFACE
read -p "Public IPv6 prefix for tortuga (e.g., 2601:516:84fa:af55::/64): " PUBLIC_IPV6_PREFIX
read -p "Tortuga public endpoint (e.g., 1.2.3.4:51820): " TORTUGA_ENDPOINT

echo ""
echo -e "${GREEN}Generating WireGuard keys...${NC}"

# Generate server (tortuga) keys
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Generate client (atlantis) keys
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# Generate shared preshared key
PRESHARED_KEY=$(wg genpsk)

echo -e "${GREEN}Keys generated successfully${NC}"
echo ""

# Display keys for verification
echo -e "${YELLOW}Generated keys (for reference):${NC}"
echo "Server (tortuga) public key: $SERVER_PUBLIC_KEY"
echo "Client (atlantis) public key: $CLIENT_PUBLIC_KEY"
echo ""

# Vaults for each cluster
TORTUGA_VAULT="kube-tortuga"
ATLANTIS_VAULT="kube-atlantis"

echo -e "${GREEN}Creating 1Password items...${NC}"
echo ""

# Create server item (wg-server)
echo "Creating wg-server in $TORTUGA_VAULT vault..."
op item create \
    --vault "$TORTUGA_VAULT" \
    --category "Server" \
    --title "wg-server" \
    --tags "wireguard,kubernetes,tortuga" \
    "private_key=$SERVER_PRIVATE_KEY" \
    "peer_atlantis_pubkey=$CLIENT_PUBLIC_KEY" \
    "peer_atlantis_psk=$PRESHARED_KEY" \
    "wan_interface=$WAN_INTERFACE" \
    "public_ipv6_prefix=$PUBLIC_IPV6_PREFIX" \
    > /dev/null

echo -e "${GREEN}Created wg-server${NC}"

# Create client item (wg-vpn-router)
echo "Creating wg-vpn-router in $ATLANTIS_VAULT vault..."
op item create \
    --vault "$ATLANTIS_VAULT" \
    --category "Server" \
    --title "wg-vpn-router" \
    --tags "wireguard,kubernetes,atlantis" \
    "private_key=$CLIENT_PRIVATE_KEY" \
    "peer_tortuga_pubkey=$SERVER_PUBLIC_KEY" \
    "peer_tortuga_psk=$PRESHARED_KEY" \
    "peer_tortuga_endpoint=$TORTUGA_ENDPOINT" \
    > /dev/null

echo -e "${GREEN}Created wg-vpn-router${NC}"

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "1Password items created:"
echo "  - wg-server (in $TORTUGA_VAULT vault)"
echo "  - wg-vpn-router (in $ATLANTIS_VAULT vault)"
