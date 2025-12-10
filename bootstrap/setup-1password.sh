#!/usr/bin/env zsh
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}1Password Connect Setup for Kubernetes${NC}"
echo "========================================"
echo ""

# Check for required tools
for cmd in op kubectl; do
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

# Get list of vaults and let user select
echo -e "${CYAN}Available vaults:${NC}"
vaults=("${(@f)$(op vault list --format=json | jq -r '.[].name')}")
for i in {1..${#vaults[@]}}; do
    echo "  $i. ${vaults[$i]}"
done
echo ""
read "vault_choice?Select vault number: "
VAULT="${vaults[$vault_choice]}"
echo -e "${GREEN}Selected vault: ${VAULT}${NC}"
echo ""

# Get list of DOCUMENT items (credentials JSON files)
echo -e "${CYAN}Select the Connect Server credentials item:${NC}"
creds_items=("${(@f)$(op item list --vault "$VAULT" --format=json | jq -r '.[] | select(.category == "DOCUMENT") | .title')}")
for i in {1..${#creds_items[@]}}; do
    echo "  $i. ${creds_items[$i]}"
done
echo ""
read "creds_choice?Select credentials item number: "
CREDS_ITEM="${creds_items[$creds_choice]}"
echo -e "${GREEN}Selected: ${CREDS_ITEM}${NC}"
echo ""

# Get the credentials JSON and encode it
echo -e "${YELLOW}Fetching and encoding credentials...${NC}"
# Get the credential file attachment using op read with secret reference
CREDS_JSON=$(op read "op://${VAULT}/${CREDS_ITEM}/1password-credentials.json")
# Base64 encode with URL-safe alphabet, no padding, no newlines
ENCODED_CREDS=$(echo -n "$CREDS_JSON" | base64 | tr '/+' '_-' | tr -d '=' | tr -d '\n')
echo -e "${GREEN}Credentials encoded${NC}"
echo ""

# Get list of API_CREDENTIAL items (access tokens)
echo -e "${CYAN}Select the Connect Server access token item:${NC}"
token_items=("${(@f)$(op item list --vault "$VAULT" --format=json | jq -r '.[] | select(.category == "API_CREDENTIAL") | .title')}")
for i in {1..${#token_items[@]}}; do
    echo "  $i. ${token_items[$i]}"
done
echo ""
read "token_choice?Select token item number: "
TOKEN_ITEM="${token_items[$token_choice]}"
echo -e "${GREEN}Selected: ${TOKEN_ITEM}${NC}"
echo ""

# Get the access token
echo -e "${YELLOW}Fetching access token...${NC}"
ACCESS_TOKEN=$(op item get "$TOKEN_ITEM" --vault "$VAULT" --fields credential --reveal)
echo -e "${GREEN}Token retrieved${NC}"
echo ""

# Create the namespace if it doesn't exist
echo -e "${YELLOW}Creating external-secrets namespace...${NC}"
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Create the credentials secret
echo -e "${YELLOW}Creating op-credentials secret...${NC}"
kubectl create secret generic op-credentials \
    --namespace external-secrets \
    --from-literal="1password-credentials.json=${ENCODED_CREDS}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create the token secret
echo -e "${YELLOW}Creating onepassword-token secret...${NC}"
kubectl create secret generic onepassword-token \
    --namespace external-secrets \
    --from-literal="token=${ACCESS_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Created secrets in external-secrets namespace:"
echo "  - op-credentials (1password-credentials.json)"
echo "  - onepassword-token (token)"
