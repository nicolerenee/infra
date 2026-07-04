# Janet brain (in-cluster web service) — janet namespace on fairy.
#
# ESO identity + app config for the brain. The brain is KEYLESS toward
# Anthropic (the AI gateway injects the key). Two separate GSM secrets:
#
#   fairy-k8s01-janet-google — Google OAuth client id + secret for the
#     calendar/email vault. Externally issued (Google console), so tofu owns
#     only the container; the value is pushed by hand, never in state:
#       printf '{"GOOGLE_CLIENT_ID":"<id>","GOOGLE_CLIENT_SECRET":"<secret>"}' | \
#         gcloud secrets versions add fairy-k8s01-janet-google \
#           --project=freckle-secrets-db8d4f --data-file=-
#
#   fairy-k8s01-janet-oidc — Janet's pocket-id (Freckle ID) client id. tofu
#     GENERATES this client (pocketid_client.janet), so it also stores the
#     value via the gsm-secret module — same as the cloudflare tunnel token.
#     No manual step. (Client ids aren't secret, but sourcing from GSM keeps
#     them out of this PUBLIC repo.)
resource "google_secret_manager_secret" "janet_google" {
  secret_id = "fairy-k8s01-janet-google"
  project   = local.project_id

  labels = {
    cluster   = "fairy-k8s01"
    namespace = "janet"
    consumer  = "janet-brain"
  }

  replication {
    auto {}
  }
}

#   fairy-k8s01-janet-github — the "janet" GitHub App's OAuth client id +
#     secret, for the per-user token vault behind background coding runs.
#     Externally issued (GitHub App registration), so tofu owns only the
#     container; the value is pushed by hand, never in state — same as
#     janet-google:
#       printf '{"GITHUB_CLIENT_ID":"<id>","GITHUB_CLIENT_SECRET":"<secret>"}' | \
#         gcloud secrets versions add fairy-k8s01-janet-github \
#           --project=freckle-secrets-db8d4f --data-file=-
#     The vault is encrypted with the existing JANET_TOKEN_ENC_KEY (reused, not
#     a new key). Covered by the janet eso-namespace prefix grant.
resource "google_secret_manager_secret" "janet_github" {
  secret_id = "fairy-k8s01-janet-github"
  project   = local.project_id

  labels = {
    cluster   = "fairy-k8s01"
    namespace = "janet"
    consumer  = "janet-brain"
  }

  replication {
    auto {}
  }
}

# OIDC client id, stored by tofu since tofu mints it. Final secret_id is
# `fairy-k8s01-janet-oidc`, covered by the janet eso-namespace prefix grant.
module "janet_oidc" {
  source = "./modules/gsm-secret"

  cluster             = "fairy-k8s01"
  namespace           = "janet"
  name                = "oidc"
  secret_data         = pocketid_client.janet.id
  workload_project_id = local.project_id
  extra_labels = {
    consumer = "janet-brain"
  }
}

# AES-256 key for encrypting the Google token vault at rest (§16). tofu mints
# 32 random bytes (hex) and stores them in GSM — no hand-entry. The brain
# requires JANET_TOKEN_ENC_KEY whenever DATABASE_URL is set.
resource "random_bytes" "janet_token_enc" {
  length = 32
}

module "janet_token_enc" {
  source = "./modules/gsm-secret"

  cluster             = "fairy-k8s01"
  namespace           = "janet"
  name                = "token-enc"
  secret_data         = random_bytes.janet_token_enc.hex
  workload_project_id = local.project_id
  extra_labels = {
    consumer = "janet-brain"
  }
}

# secretAccessor grant for the janet ns ESO identity — covers every secret in
# `fairy-k8s01-janet-*`.
module "janet_eso" {
  source = "./modules/eso-namespace"

  cluster                 = "fairy-k8s01"
  namespace               = "janet"
  sa_name                 = "external-secrets-janet"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}
