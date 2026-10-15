#!/usr/bin/env bash
# Vendor the kubevirt/containerized-data-importer release manifests
# (operator + CR) into kubernetes/apps/kubevirt/{cdi-operator,cdi-cr}/.
#
# The upstream operator manifest ships with a `Namespace: cdi` resource
# as its first doc; we strip that out so the namespace stays under the
# Flux scaffolding in kubernetes/clusters/*/flux/kubevirt.yaml.
#
# To re-vendor manually:   ./scripts/vendor-cdi.sh
# To check without writing: ./scripts/vendor-cdi.sh --check
#
# Requires: yq (mikefarah), curl.

set -euo pipefail

# renovate: datasource=github-releases depName=kubevirt/containerized-data-importer
TAG=v1.66.1

REPO=kubevirt/containerized-data-importer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="${SCRIPT_DIR}/../kubernetes/apps/kubevirt"
mkdir -p "${DEST_ROOT}/cdi-operator" "${DEST_ROOT}/cdi-cr"
DEST_ROOT="$(cd "${DEST_ROOT}" && pwd)"
OP_DIR="${DEST_ROOT}/cdi-operator"
CR_DIR="${DEST_ROOT}/cdi-cr"

MODE=${1:-vendor}
case "${MODE}" in
  vendor|--check) ;;
  --help|-h)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *)
    echo "ERROR: unknown argument '${MODE}'. Use --check, --help, or no args." >&2
    exit 64 ;;
esac

command -v yq >/dev/null || { echo "ERROR: yq (mikefarah) required" >&2; exit 2; }
command -v curl >/dev/null || { echo "ERROR: curl required" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

{
  cat <<EOF
# Vendored from ${REPO} @ ${TAG}
# Source: ${BASE_URL}/cdi-operator.yaml
# Namespace doc stripped; ns is owned by kubernetes/clusters/*/flux/kubevirt.yaml.
# To bump: change TAG in scripts/vendor-cdi.sh and re-run.
---
EOF
  curl -fsSL "${BASE_URL}/cdi-operator.yaml" \
    | yq eval 'select(.kind != "Namespace")' -
} > "${WORK}/cdi-operator.yaml"

{
  cat <<EOF
# Vendored from ${REPO} @ ${TAG}
# Source: ${BASE_URL}/cdi-cr.yaml
# To bump: change TAG in scripts/vendor-cdi.sh and re-run.
---
EOF
  curl -fsSL "${BASE_URL}/cdi-cr.yaml"
} > "${WORK}/cdi-cr.yaml"

cat > "${WORK}/operator-kustomization.yaml" <<'EOF'
---
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
# Vendored upstream CDI operator manifest. To bump, change TAG in
# scripts/vendor-cdi.sh and re-run (or let Renovate bump it).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./cdi-operator.yaml
EOF

cat > "${WORK}/cr-kustomization.yaml" <<'EOF'
---
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
# CDI CR — vendored at the same TAG as the operator. Edits beyond upstream
# defaults live in this kustomization (patches/), not the vendored CR file.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./cdi-cr.yaml
  # Ours, not upstream: claim property sets for CSI classes CDI can't infer.
  - ./storageprofiles.yaml
EOF

if [[ "${MODE}" == "--check" ]]; then
  fail=0
  diff -q "${OP_DIR}/cdi-operator.yaml" "${WORK}/cdi-operator.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cdi-operator/cdi-operator.yaml"; fail=1; }
  diff -q "${OP_DIR}/kustomization.yaml" "${WORK}/operator-kustomization.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cdi-operator/kustomization.yaml"; fail=1; }
  diff -q "${CR_DIR}/cdi-cr.yaml" "${WORK}/cdi-cr.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cdi-cr/cdi-cr.yaml"; fail=1; }
  diff -q "${CR_DIR}/kustomization.yaml" "${WORK}/cr-kustomization.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cdi-cr/kustomization.yaml"; fail=1; }
  if [[ ${fail} -eq 0 ]]; then
    echo "OK: vendored CDI manifests match ${REPO}@${TAG}"
  fi
  exit ${fail}
fi

echo "Vendoring ${REPO}@${TAG} -> ${OP_DIR}, ${CR_DIR}"
cp "${WORK}/cdi-operator.yaml"           "${OP_DIR}/cdi-operator.yaml"
cp "${WORK}/operator-kustomization.yaml" "${OP_DIR}/kustomization.yaml"
cp "${WORK}/cdi-cr.yaml"                 "${CR_DIR}/cdi-cr.yaml"
cp "${WORK}/cr-kustomization.yaml"       "${CR_DIR}/kustomization.yaml"
echo "Done."
