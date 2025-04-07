#!/bin/bash

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
