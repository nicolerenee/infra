#!/usr/bin/env bash
# Vendor the kubernetes-sigs/gateway-api standard-channel CRDs into
# kubernetes/apps/networking/gateway-api/.
#
# Run by Renovate (via postUpgradeTasks in .renovaterc.json5) when the TAG
# below is bumped, and by CI in --check mode on every PR to ensure the
# vendored content matches the pinned tag.
#
# To re-vendor manually:   ./scripts/vendor-gateway-api-crds.sh
# To check without writing: ./scripts/vendor-gateway-api-crds.sh --check
#
# Requires the `gh` CLI (auth via GH_TOKEN env or `gh auth login`).

set -euo pipefail

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
TAG=v1.5.1

REPO=kubernetes-sigs/gateway-api
UPSTREAM_PATH=config/crd/standard
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$(cd "${SCRIPT_DIR}/../kubernetes/apps/networking/gateway-api" && pwd)"

MODE=${1:-vendor}

if [[ "${MODE}" == "--help" || "${MODE}" == "-h" ]]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

command -v gh >/dev/null || { echo "ERROR: gh CLI required" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# Fetch upstream file list, then download each with a provenance header
# into the temp dir.
mapfile -t UPSTREAM_FILES < <(gh api "repos/${REPO}/contents/${UPSTREAM_PATH}?ref=${TAG}" --jq '.[].name')
[[ ${#UPSTREAM_FILES[@]} -gt 0 ]] || { echo "ERROR: no files at ${REPO}/${UPSTREAM_PATH}@${TAG}" >&2; exit 1; }

for f in "${UPSTREAM_FILES[@]}"; do
  {
    cat <<EOF
# Vendored from ${REPO} @ ${TAG}
# Source: https://github.com/${REPO}/blob/${TAG}/${UPSTREAM_PATH}/${f}
# To bump: bump TAG in scripts/vendor-gateway-api-crds.sh and re-run.
EOF
    gh api "repos/${REPO}/contents/${UPSTREAM_PATH}/${f}?ref=${TAG}" --jq '.content' | base64 -d
  } > "${WORK}/${f}"
done

# Render expected kustomization.yaml so --check can compare it too.
{
  cat <<'EOF'
---
# yaml-language-server: $schema=https://www.schemastore.org/kustomization.json
# Vendored CRDs. To bump, change TAG in scripts/vendor-gateway-api-crds.sh
# and re-run (or let Renovate do it automatically on a tag bump).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOF
  for f in "${UPSTREAM_FILES[@]}"; do
    echo "  - ./${f}"
  done
} > "${WORK}/kustomization.yaml"

if [[ "${MODE}" == "--check" ]]; then
  fail=0
  for f in "${UPSTREAM_FILES[@]}" kustomization.yaml; do
    if ! diff -q "${DEST_DIR}/${f}" "${WORK}/${f}" >/dev/null 2>&1; then
      echo "MISMATCH: ${f}"
      diff "${DEST_DIR}/${f}" "${WORK}/${f}" | head -20 || true
      fail=1
    fi
  done
  # Flag orphan vendored files that no longer exist upstream.
  while IFS= read -r local_file; do
    name=$(basename "${local_file}")
    [[ "${name}" == "kustomization.yaml" ]] && continue
    if ! printf '%s\n' "${UPSTREAM_FILES[@]}" | grep -qx "${name}"; then
      echo "ORPHAN (no longer in upstream): ${name}"
      fail=1
    fi
  done < <(find "${DEST_DIR}" -maxdepth 1 -name '*.yaml')
  if [[ ${fail} -eq 0 ]]; then
    echo "OK: vendored CRDs in ${DEST_DIR##*/kubernetes/} match ${REPO}@${TAG}"
  fi
  exit ${fail}
fi

# Vendor mode: wipe existing CRD YAMLs (keep kustomization.yaml for the
# moment), copy new ones, regenerate the kustomization.yaml.
echo "Vendoring ${REPO}@${TAG} -> ${DEST_DIR}"
find "${DEST_DIR}" -maxdepth 1 -name '*.yaml' ! -name 'kustomization.yaml' -delete
for f in "${UPSTREAM_FILES[@]}"; do
  cp "${WORK}/${f}" "${DEST_DIR}/${f}"
done
cp "${WORK}/kustomization.yaml" "${DEST_DIR}/kustomization.yaml"

echo "Done. ${#UPSTREAM_FILES[@]} files vendored."
