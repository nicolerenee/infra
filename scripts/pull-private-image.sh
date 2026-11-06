#!/usr/bin/env bash
# Pre-pull a private GHCR image onto one node through kubelet, with the
# cluster's existing ghcr-pull credential.
#
# Usage: pull-private-image.sh <image> <node-internal-ip>
#
# Talos's image pull API authenticates only through machine-config registry
# auth, so it fetches private freckleapps packages anonymously and GHCR
# answers 401. kubelet pulls them with a Pod's imagePullSecrets, the same path
# the workloads use. The Pod mounts the image as an image volume beside a
# pause container, so the image is pulled into the node's containerd store
# (where spegel shares it) but none of its code runs. The credential stays in
# the cluster: this script only names the Secret and never reads it.
#
# Fails closed: a bad ref, an unknown node, a missing Secret, any pull failure
# event, a failed Pod or a timeout all exit non-zero.
set -euo pipefail

IMAGE="${1:?image}"
TARGET_IP="${2:?node internal IP}"
NAMESPACE="${PULL_NAMESPACE:-image-pull-check}"
TIMEOUT="${PULL_TIMEOUT_SECONDS:-600}"
INTERVAL="${PULL_POLL_SECONDS:-5}"
PAUSE_IMAGE="registry.k8s.io/pause:3.10"
SA_DIR="${SA_DIR:-/var/run/secrets/kubernetes.io/serviceaccount}"
API="${KUBE_API:-https://kubernetes.default.svc}"

# The ref is interpolated into a JSON body: accept only the characters an
# image reference can contain, and only the private org this path is for.
ref_re='^ghcr\.io/freckleapps/[a-z0-9]+([._/-][a-z0-9]+)*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?(@sha256:[0-9a-f]{64})?$'
if [[ ! "${IMAGE}" =~ ${ref_re} ]]; then
  echo "::error::refusing unexpected private image reference: ${IMAGE}"
  exit 1
fi

kube() {
  local method="$1" path="$2"
  shift 2
  curl -fsS --cacert "${SA_DIR}/ca.crt" \
    -H "Authorization: Bearer $(cat "${SA_DIR}/token")" \
    -X "${method}" "$@" "${API}${path}"
}

node=$(kube GET /api/v1/nodes \
  | TARGET_IP="${TARGET_IP}" yq -p json \
    '[.items[] | select(.status.addresses[] | select(.type == "InternalIP" and .address == strenv(TARGET_IP))) | .metadata.name] | .[0] // ""')
if [[ ! "${node}" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$ ]]; then
  echo "::error::no node has InternalIP ${TARGET_IP}"
  exit 1
fi

# Metadata only: the API never sends the Secret's data to this runner.
secrets=$(kube GET "/api/v1/namespaces/${NAMESPACE}/secrets?fieldSelector=metadata.name%3Dghcr-pull" \
  -H 'Accept: application/json;as=PartialObjectMetadataList;g=meta.k8s.io;v=v1' \
  | yq -p json '.items | length')
if [[ "${secrets}" != "1" ]]; then
  echo "::error::${NAMESPACE}/ghcr-pull is missing; the namespace must opt in to the ghcr-pull ClusterExternalSecret"
  exit 1
fi

body=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "generateName": "image-pull-",
    "labels": {"app.kubernetes.io/name": "image-pull-check"}
  },
  "spec": {
    "nodeName": "${node}",
    "restartPolicy": "Never",
    "activeDeadlineSeconds": $((TIMEOUT + 300)),
    "automountServiceAccountToken": false,
    "enableServiceLinks": false,
    "imagePullSecrets": [{"name": "ghcr-pull"}],
    "securityContext": {
      "runAsNonRoot": true,
      "runAsUser": 65535,
      "runAsGroup": 65535,
      "seccompProfile": {"type": "RuntimeDefault"}
    },
    "tolerations": [{"operator": "Exists"}],
    "containers": [{
      "name": "pause",
      "image": "${PAUSE_IMAGE}",
      "resources": {"requests": {"cpu": "1m", "memory": "4Mi"}, "limits": {"memory": "16Mi"}},
      "securityContext": {
        "allowPrivilegeEscalation": false,
        "readOnlyRootFilesystem": true,
        "capabilities": {"drop": ["ALL"]}
      },
      "volumeMounts": [{"name": "image", "mountPath": "/image", "readOnly": true}]
    }],
    "volumes": [{"name": "image", "image": {"reference": "${IMAGE}", "pullPolicy": "Always"}}]
  }
}
EOF
)

pod=$(kube POST "/api/v1/namespaces/${NAMESPACE}/pods" \
  -H 'Content-Type: application/json' --data-binary "${body}" \
  | yq -p json '.metadata.name')
if [[ ! "${pod}" =~ ^image-pull-[a-z0-9]+$ ]]; then
  echo "::error::Pod creation returned no name"
  exit 1
fi
cleanup() {
  kube DELETE "/api/v1/namespaces/${NAMESPACE}/pods/${pod}" -o /dev/null || true
}
trap cleanup EXIT

echo "Pulling ${IMAGE} on ${node} through kubelet (${NAMESPACE}/${pod})"
deadline=$((SECONDS + TIMEOUT))
while :; do
  phase=$(kube GET "/api/v1/namespaces/${NAMESPACE}/pods/${pod}" | yq -p json '.status.phase // ""')
  case "${phase}" in
    Running | Succeeded)
      echo "Pulled ${IMAGE} on ${node}"
      exit 0
      ;;
    Failed)
      echo "::error::${NAMESPACE}/${pod} failed before the pull completed"
      exit 1
      ;;
  esac

  # One pull failure fails the check, like the single talosctl attempt does.
  # Event messages name the image and the registry's answer, never credentials.
  failure=$(kube GET "/api/v1/namespaces/${NAMESPACE}/events?fieldSelector=involvedObject.name%3D${pod}" \
    | yq -p json '[.items[] | select(.type == "Warning" and (.reason == "Failed" or .reason == "BackOff" or .reason == "ErrImagePull" or .reason == "ImagePullBackOff" or .reason == "FailedMount" or .reason == "FailedCreatePodSandBox")) | .reason + ": " + .message] | .[0] // ""')
  if [[ -n "${failure}" ]]; then
    echo "::error::kubelet could not pull ${IMAGE} on ${node}: ${failure}"
    exit 1
  fi

  if ((SECONDS >= deadline)); then
    echo "::error::timed out after ${TIMEOUT}s pulling ${IMAGE} on ${node}"
    exit 1
  fi
  sleep "${INTERVAL}"
done
