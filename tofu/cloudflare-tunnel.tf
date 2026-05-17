# Per-cluster Cloudflare tunnels. Public traffic enters via Cloudflare's
# edge → cloudflared in-cluster → envoy tunnel gateway → HTTPRoute. Per-app
# DNS is handled by external-dns watching HTTPRoutes; this file owns just
# the boundary stuff:
#   - the tunnel itself
#   - the tunnel token (stored in GSM for ESO to pull)
#   - the bootstrap CNAME pointing at the tunnel
#   - federated-principal IAM grant so ESO in the cloudflared ns can read
#
# Adding a tunnel for a new cluster: flip `has_cf_tunnel = true` on the
# cluster's entry in `local.clusters_config`. Everything below provisions
# off that single flag.
locals {
  cf_tunnel_clusters = {
    for k, v in local.clusters_config : k => v if v.has_cf_tunnel
  }
}

resource "random_id" "tunnel_secret" {
  for_each = local.cf_tunnel_clusters

  byte_length = 35
  keepers = {
    # Bump to rotate the tunnel's signing secret. Forces tunnel replacement.
    version = "v1"
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  for_each = local.cf_tunnel_clusters

  account_id    = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  name          = each.key
  tunnel_secret = random_id.tunnel_secret[each.key].b64_std
  # cloudflared reads /etc/cloudflared/config.yaml from a ConfigMap
  # (kubernetes/apps/networking/cloudflare-tunnel/files/config.yaml).
  # Local config is fully manageable; the API-side config resource
  # can't be destroyed cleanly.
  config_src = "local"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "tunnel" {
  for_each = local.cf_tunnel_clusters

  account_id = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel[each.key].id
}

# Tunnel token in GSM via the gsm-secret module. Final secret_id is
# `<cluster>-cloudflared-tunnel-token` — covered by the namespace-prefix
# IAM grant on the cloudflared ns below.
module "tunnel_token" {
  source   = "./modules/gsm-secret"
  for_each = local.cf_tunnel_clusters

  cluster             = each.key
  namespace           = "cloudflared"
  name                = "tunnel-token"
  secret_data         = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel[each.key].token
  workload_project_id = local.project_id
}

# Bootstrap CNAME: <cluster>-cf-tun-gw.freckle.systems → tunnel UUID.
# Flat per-cluster naming avoids per-cluster subdomain hierarchies and
# works as the fleet grows.
resource "cloudflare_dns_record" "cf_tun_gw" {
  for_each = local.cf_tunnel_clusters

  zone_id = cloudflare_zone.freckle_systems.id
  name    = "${each.key}-cf-tun-gw"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel[each.key].id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # 'auto' when proxied
  comment = "Managed by tofu (cloudflare-tunnel.tf)"
}

# Project-level secretAccessor grant for the cloudflared ns ESO identity.
# Single binding covers every secret in `<cluster>-cloudflared-*`.
module "cloudflared_eso" {
  source   = "./modules/eso-namespace"
  for_each = local.cf_tunnel_clusters

  cluster                 = each.key
  namespace               = "cloudflared"
  sa_name                 = "external-secrets-cloudflared"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}

# State migrations from the fairy-specific resource names to the
# per-cluster for_each shape. Source has no key; destination has the
# cluster key — tofu maps these cleanly.
moved {
  from = random_id.fairy_tunnel_secret
  to   = random_id.tunnel_secret["fairy-k8s01"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.fairy
  to   = cloudflare_zero_trust_tunnel_cloudflared.tunnel["fairy-k8s01"]
}

moved {
  from = cloudflare_dns_record.fairy_cf_tun_gw
  to   = cloudflare_dns_record.cf_tun_gw["fairy-k8s01"]
}

moved {
  from = module.fairy_cloudflared_tunnel_token
  to   = module.tunnel_token["fairy-k8s01"]
}

moved {
  from = module.fairy_cloudflared_eso
  to   = module.cloudflared_eso["fairy-k8s01"]
}
