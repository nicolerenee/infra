# Per-cluster API server DNS endpoints. Resolves to one or more control
# plane node IPs (LAN-side). NOT proxied through Cloudflare — apiserver
# traffic terminates directly on the node, with the cluster's own CA on
# both ends, so any CF interposition would just break TLS.
#
# Use case is twofold:
#   1. talos `cluster.controlPlane.endpoint` so kubelet on every node
#      and any external admin (kubectl, talosctl) can find the API
#      without hardcoding an IP.
#   2. Cleanly retargeting when control plane nodes are added/removed
#      — change tofu, don't chase config files across hosts.

locals {
  # Map of cluster → list of CP node IPs to publish as A records.
  # Multiple IPs become DNS round-robin (no health checks — apiserver
  # clients are generally fine with TCP-level retry on stale entries,
  # and on-LAN latency makes the cost of a bad RR pick negligible).
  cluster_api_endpoints = {
    "fairy-k8s01" = {
      # cn01 only for now — eventually expand to cn01..cn05 for HA.
      ips = ["10.189.3.16"]
    }
    "atlantis-k8s01" = {
      ips = ["172.26.3.5", "172.26.3.6", "172.26.3.7"]
    }
  }

  # Flatten (cluster, ip) pairs so we can use a single for_each.
  cluster_api_endpoint_records = merge([
    for cluster, ep in local.cluster_api_endpoints : {
      for ip in ep.ips :
      "${cluster}-${ip}" => {
        cluster = cluster
        ip      = ip
      }
    }
  ]...)
}

resource "cloudflare_dns_record" "cluster_api" {
  for_each = local.cluster_api_endpoint_records

  zone_id = cloudflare_zone.freckle_systems.id
  name    = "${each.value.cluster}-api"
  type    = "A"
  content = each.value.ip
  proxied = false # apiserver TLS terminates on the node; never proxy.
  ttl     = 120
}

# Adopt the existing fairy-k8s01-api record (manually created before this
# file existed) instead of clobbering it on first apply.
data "cloudflare_dns_records" "fairy_api_existing" {
  zone_id = cloudflare_zone.freckle_systems.id
  name = {
    exact = "fairy-k8s01-api.freckle.systems"
  }
  type = "A"
}

import {
  to = cloudflare_dns_record.cluster_api["fairy-k8s01-10.189.3.16"]
  id = "${cloudflare_zone.freckle_systems.id}/${data.cloudflare_dns_records.fairy_api_existing.result[0].id}"
}
