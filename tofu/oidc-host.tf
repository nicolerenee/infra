# Public host for cluster OIDC discovery + JWKS. Tailscale (and any other
# external system that needs to validate cluster-signed SA tokens) fetches
# the OIDC discovery doc from https://k8s-oidc.freckle.systems/<cluster>/
# .well-known/openid-configuration and follows jwks_uri to the JWKS.
#
# The cluster's apiserver --service-account-issuer is set to this URL
# so emitted tokens have iss matching what external validators expect.
#
# JWKS content is uploaded via `task wif:publish CLUSTER=<name>`. The
# bucket itself is just storage — tofu owns the bucket + custom domain;
# task wif owns the content lifecycle.

resource "cloudflare_r2_bucket" "k8s_oidc" {
  account_id    = var.cloudflare_account_id
  name          = "k8s-oidc"
  location      = "ENAM"
  storage_class = "Standard"
}

resource "cloudflare_r2_custom_domain" "k8s_oidc" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.k8s_oidc.name
  domain      = "k8s-oidc.freckle.systems"
  zone_id     = cloudflare_zone.freckle_systems.id
  enabled     = true
  min_tls     = "1.2"
}
