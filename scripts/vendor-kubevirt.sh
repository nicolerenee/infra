#!/usr/bin/env bash
# Vendor the kubevirt/kubevirt release manifests (operator + CR) into
# kubernetes/apps/kubevirt/{operator,cr}/.
#
# The upstream operator manifest ships with a `Namespace: kubevirt` resource
# as its first doc; we strip that out so the namespace stays under the
# Flux scaffolding in kubernetes/clusters/*/flux/kubevirt.yaml (where we
# control PSA labels and prune behaviour).
#
# To re-vendor manually:   ./scripts/vendor-kubevirt.sh
# To check without writing: ./scripts/vendor-kubevirt.sh --check
#
# Requires: yq (mikefarah), curl.

set -euo pipefail

# renovate: datasource=github-releases depName=kubevirt/kubevirt
TAG=v1.9.1

REPO=kubevirt/kubevirt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="${SCRIPT_DIR}/../kubernetes/apps/kubevirt"
mkdir -p "${DEST_ROOT}/operator" "${DEST_ROOT}/cr"
DEST_ROOT="$(cd "${DEST_ROOT}" && pwd)"
OP_DIR="${DEST_ROOT}/operator"
CR_DIR="${DEST_ROOT}/cr"

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

mkdir -p "${OP_DIR}" "${CR_DIR}"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

# Operator manifest: drop the Namespace doc (we own that elsewhere).
{
  cat <<EOF
# Vendored from ${REPO} @ ${TAG}
# Source: ${BASE_URL}/kubevirt-operator.yaml
# Namespace doc stripped; ns is owned by kubernetes/clusters/*/flux/kubevirt.yaml.
# To bump: change TAG in scripts/vendor-kubevirt.sh and re-run.
---
EOF
  curl -fsSL "${BASE_URL}/kubevirt-operator.yaml" \
    | yq eval 'select(.kind != "Namespace")' -
} > "${WORK}/kubevirt-operator.yaml"

# KubeVirt CR: vendored as-is; we'll preserve existing-cluster spec via a
# small overlay/patch in cr/kustomization.yaml if needed.
{
  cat <<EOF
# Vendored from ${REPO} @ ${TAG}
# Source: ${BASE_URL}/kubevirt-cr.yaml
# To bump: change TAG in scripts/vendor-kubevirt.sh and re-run.
---
EOF
  curl -fsSL "${BASE_URL}/kubevirt-cr.yaml"
} > "${WORK}/kubevirt-cr.yaml"

# Render expected kustomization.yaml files so --check covers them too.
cat > "${WORK}/operator-kustomization.yaml" <<'EOF'
---
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
# Vendored upstream KubeVirt operator manifest. To bump, change TAG in
# scripts/vendor-kubevirt.sh and re-run (or let Renovate bump it).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./kubevirt-operator.yaml
EOF

cat > "${WORK}/cr-kustomization.yaml" <<'EOF'
---
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
# KubeVirt CR — vendored at the same TAG as the operator. Edits beyond the
# upstream defaults live in this kustomization (patches/), not the vendored
# kubevirt-cr.yaml itself.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./kubevirt-cr.yaml
EOF

if [[ "${MODE}" == "--check" ]]; then
  fail=0
  diff -q "${OP_DIR}/kubevirt-operator.yaml" "${WORK}/kubevirt-operator.yaml" >/dev/null 2>&1 || { echo "MISMATCH: operator/kubevirt-operator.yaml"; fail=1; }
  diff -q "${OP_DIR}/kustomization.yaml"      "${WORK}/operator-kustomization.yaml" >/dev/null 2>&1 || { echo "MISMATCH: operator/kustomization.yaml"; fail=1; }
  diff -q "${CR_DIR}/kubevirt-cr.yaml"        "${WORK}/kubevirt-cr.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cr/kubevirt-cr.yaml"; fail=1; }
  diff -q "${CR_DIR}/kustomization.yaml"      "${WORK}/cr-kustomization.yaml" >/dev/null 2>&1 || { echo "MISMATCH: cr/kustomization.yaml"; fail=1; }
  if [[ ${fail} -eq 0 ]]; then
    echo "OK: vendored kubevirt manifests match ${REPO}@${TAG}"
  fi
  exit ${fail}
fi

echo "Vendoring ${REPO}@${TAG} -> ${OP_DIR}, ${CR_DIR}"
cp "${WORK}/kubevirt-operator.yaml"     "${OP_DIR}/kubevirt-operator.yaml"
cp "${WORK}/operator-kustomization.yaml" "${OP_DIR}/kustomization.yaml"
cp "${WORK}/kubevirt-cr.yaml"            "${CR_DIR}/kubevirt-cr.yaml"
cp "${WORK}/cr-kustomization.yaml"       "${CR_DIR}/kustomization.yaml"
echo "Done."
