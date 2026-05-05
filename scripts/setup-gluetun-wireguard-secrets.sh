#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TORTUGA_VAULT="kube-tortuga-k8s01"
ATLANTIS_VAULT="kube-atlantis"

echo -e "${GREEN}Gluetun WireGuard Secrets Setup${NC}"
echo "================================"
echo ""
echo "Generates WireGuard keypairs for tortuga server + VPN clients"
echo "and stores them in 1Password."
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

# Create or update a 1Password item. If the item already exists, all fields
# are overwritten with the new values.
# Usage: op_upsert <vault> <title> <tags> <field=value>...
op_upsert() {
    local vault="$1" title="$2" tags="$3"
    shift 3

    if op item get "$title" --vault "$vault" &>/dev/null; then
        echo -e "${YELLOW}  Updating existing item: $title${NC}"
        op item edit "$title" --vault "$vault" --tags "$tags" "$@" > /dev/null
    else
        echo -e "${GREEN}  Creating new item: $title${NC}"
        op item create --vault "$vault" --category "Server" \
            --title "$title" --tags "$tags" "$@" > /dev/null
    fi
}

# Prompt for tortuga endpoint
echo -e "${YELLOW}Enter configuration values:${NC}"
echo ""
read -p "Tortuga public IP: " TORTUGA_IP
read -p "Tortuga WireGuard listen port [51820]: " TORTUGA_PORT
TORTUGA_PORT=${TORTUGA_PORT:-51820}

echo ""
echo -e "${GREEN}Generating WireGuard keys...${NC}"

# Generate server (tortuga) keypair
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Generate client keypairs
REEL_PRIVATE_KEY=$(wg genkey)
REEL_PUBLIC_KEY=$(echo "$REEL_PRIVATE_KEY" | wg pubkey)
REEL_PSK=$(wg genpsk)

INK_PRIVATE_KEY=$(wg genkey)
INK_PUBLIC_KEY=$(echo "$INK_PRIVATE_KEY" | wg pubkey)
INK_PSK=$(wg genpsk)

echo -e "${GREEN}Keys generated successfully${NC}"
echo ""

# Display public keys for reference
echo -e "${YELLOW}Public keys (for reference):${NC}"
echo "  Server (tortuga):    $SERVER_PUBLIC_KEY"
echo "  Client (qbt-reel):   $REEL_PUBLIC_KEY"
echo "  Client (qbt-ink):    $INK_PUBLIC_KEY"
echo ""

echo -e "${GREEN}Saving to 1Password...${NC}"
echo ""

# WireGuard server item — used by ExternalSecret on tortuga for WireGuard gateway
op_upsert "$TORTUGA_VAULT" "wg-server" "wireguard,tortuga" \
    "private_key=$SERVER_PRIVATE_KEY" \
    "listen_port=$TORTUGA_PORT" \
    "qbt_reel_pubkey=$REEL_PUBLIC_KEY" \
    "qbt_reel_psk=$REEL_PSK" \
    "qbt_ink_pubkey=$INK_PUBLIC_KEY" \
    "qbt_ink_psk=$INK_PSK"

echo ""

# Client items — used by ExternalSecrets for gluetun env vars on atlantis
op_upsert "$ATLANTIS_VAULT" "gluetun-qbt-reel" "wireguard,gluetun,atlantis" \
    "WIREGUARD_PRIVATE_KEY=$REEL_PRIVATE_KEY" \
    "WIREGUARD_PRESHARED_KEY=$REEL_PSK" \
    "WIREGUARD_PUBLIC_KEY=$SERVER_PUBLIC_KEY" \
    "VPN_ENDPOINT_IP=$TORTUGA_IP" \
    "VPN_ENDPOINT_PORT=$TORTUGA_PORT" \
    "WIREGUARD_ADDRESSES=10.66.0.10/32"

op_upsert "$ATLANTIS_VAULT" "gluetun-qbt-ink" "wireguard,gluetun,atlantis" \
    "WIREGUARD_PRIVATE_KEY=$INK_PRIVATE_KEY" \
    "WIREGUARD_PRESHARED_KEY=$INK_PSK" \
    "WIREGUARD_PUBLIC_KEY=$SERVER_PUBLIC_KEY" \
    "VPN_ENDPOINT_IP=$TORTUGA_IP" \
    "VPN_ENDPOINT_PORT=$TORTUGA_PORT" \
    "WIREGUARD_ADDRESSES=10.66.0.11/32"

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "1Password items created/updated:"
echo "  - wg-server (in $TORTUGA_VAULT vault) — WireGuard server keys, for tortuga ExternalSecret"
echo "  - gluetun-qbt-reel (in $ATLANTIS_VAULT vault) — for atlantis ExternalSecret"
echo "  - gluetun-qbt-ink (in $ATLANTIS_VAULT vault) — for atlantis ExternalSecret"
echo ""
echo "Next steps:"
echo "  1. Deploy the WireGuard gateway on tortuga-k8s01"
echo "  2. Add gluetun sidecars to qbt pods on atlantis-k8s01"
