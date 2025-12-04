#!/bin/bash

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.4.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
