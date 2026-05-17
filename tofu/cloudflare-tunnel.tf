# Cloudflare tunnel for fairy-k8s01. Public traffic enters via Cloudflare's
# edge → cloudflared in-cluster → envoy tunnel gateway → HTTPRoute. Per-app
# DNS is handled by external-dns watching HTTPRoutes; this file owns just
# the boundary stuff:
#   - the tunnel itself
#   - the tunnel token (stored in GSM for ESO to pull)
#   - the bootstrap CNAME pointing at the tunnel
#   - federated-principal IAM grant so ESO in the networking ns can read

resource "random_id" "fairy_tunnel_secret" {
  byte_length = 35
  keepers = {
    # Bump to rotate the tunnel's signing secret. Forces tunnel replacement.
    version = "v1"
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "fairy" {
  account_id    = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  name          = "fairy-k8s01"
  tunnel_secret = random_id.fairy_tunnel_secret.b64_std
  config_src    = "local" # cloudflared reads /etc/cloudflared/config.yaml from a ConfigMap (kubernetes/apps/networking/cloudflare-tunnel/files/config.yaml). Local config is fully manageable; the API-side config resource can't be destroyed cleanly.
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "fairy" {
  account_id = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.fairy.id
}

# Tunnel token in GSM via the gsm-secret module. Final secret_id is
# `fairy-k8s01-cloudflared-tunnel-token` — matches the namespace-prefix
# IAM grant created below by the eso-namespace module.
module "fairy_cloudflared_tunnel_token" {
  source = "./modules/gsm-secret"

  cluster             = "fairy-k8s01"
  namespace           = "cloudflared"
  name                = "tunnel-token"
  secret_data         = data.cloudflare_zero_trust_tunnel_cloudflared_token.fairy.token
  workload_project_id = local.project_id
}

# Bootstrap CNAME: fairy-k8s01-cf-tun-gw.freckle.systems → tunnel.
# Per-cluster naming using the full cluster name flattens nicely under
# the apex and avoids per-cluster subdomain hierarchies — works equally
# well when atlantis has multiple clusters. Per-app records are managed
# by external-dns watching HTTPRoutes in-cluster.
resource "cloudflare_dns_record" "fairy_cf_tun_gw" {
  zone_id = cloudflare_zone.freckle_systems.id
  name    = "fairy-k8s01-cf-tun-gw"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.fairy.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # 'auto' when proxied
}

# Project-level secretAccessor grant for the cloudflared namespace's ESO
# identity. The eso-namespace module owns the IAM condition shape (prefix
# match on `<cluster>-<namespace>-`) so this binding covers any future
# GSM secret named `fairy-k8s01-cloudflared-*` without re-binding.
module "fairy_cloudflared_eso" {
  source = "./modules/eso-namespace"

  cluster                 = "fairy-k8s01"
  namespace               = "cloudflared"
  sa_name                 = "external-secrets-cloudflared"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}

# Resource address migration: the IAM binding + GSM secret + version
# moved into the new modules. State edits keep tofu plan empty.
moved {
  from = google_project_iam_member.fairy_cloudflared_eso_accessor
  to   = module.fairy_cloudflared_eso.google_project_iam_member.accessor
}

moved {
  from = google_secret_manager_secret.fairy_tunnel_token
  to   = module.fairy_cloudflared_tunnel_token.google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_version.fairy_tunnel_token
  to   = module.fairy_cloudflared_tunnel_token.google_secret_manager_secret_version.this
}
