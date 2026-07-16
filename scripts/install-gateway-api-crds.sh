#!/bin/bash
# Bootstrap-time install of Gateway API CRDs. After Flux is reconciling the
# gateway-api-crds Kustomization (kubernetes/apps/networking/gateway-api/),
# this script is only needed on fresh cluster bring-up to seed the CRDs
# before envoy-gateway can come up.
#
# As of v1.5.x, TLSRoute is in the standard channel; the previously-needed
# separate experimental TLSRoute apply has been removed.

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
