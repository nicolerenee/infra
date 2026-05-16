# Per-cluster OIDC issuer URI + JWKS contents for WIF provider registration.
# Populated by `task wif:bootstrap CLUSTER=<name>` which writes to
# clusters.auto.tfvars.json. JWKS contents are public keys, safe to commit.
variable "clusters" {
  description = "Per-cluster OIDC discovery data used to register WIF providers with inline JWKS (no public bucket required)."
  type = map(object({
    issuer_uri = string
    jwks_json  = string
  }))
  default = {}
}

