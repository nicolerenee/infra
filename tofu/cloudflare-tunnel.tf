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

# Tunnel token in GSM. Name matches the fairy-k8s01-networking- prefix so
# ESO's networking-namespace federated principal can read it.
resource "google_secret_manager_secret" "fairy_tunnel_token" {
  secret_id = "fairy-k8s01-networking-cloudflared-tunnel-token"
  project   = local.project_id

  labels = {
    cluster   = "fairy-k8s01"
    namespace = "networking"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "fairy_tunnel_token" {
  secret      = google_secret_manager_secret.fairy_tunnel_token.id
  secret_data = data.cloudflare_zero_trust_tunnel_cloudflared_token.fairy.token
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

# IAM: ESO in the networking namespace can read fairy-k8s01-networking-*
# secrets. Direct federated-principal binding — no GCP SA in the middle.
# Cleaner than our other namespace_bindings (which create GCP SAs); we'll
# refactor those to match this pattern later.
resource "google_project_iam_member" "fairy_networking_eso_accessor" {
  project = local.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:networking:external-secrets-networking"

  condition {
    title       = "fairy-k8s01-networking-ns"
    description = "ESO in fairy networking namespace can read fairy-k8s01-networking-* secrets"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/fairy-k8s01-networking-\")"
  }
}
