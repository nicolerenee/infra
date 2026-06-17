# Janet brain (in-cluster web service) — janet namespace on fairy.
#
# ESO identity + app secrets for the brain. The brain is KEYLESS toward
# Anthropic (the AI gateway injects the key), so the only real secret here is
# the Google OAuth client secret for the calendar/email vault. The pocket-id
# OIDC client is public/PKCE (no secret); its generated client id is non-secret
# but sourced via GSM too so the UUID isn't hardcoded in manifests.
#
# Tofu owns the secret EXISTENCE; the value is pushed by hand, never in state.
# Value is a JSON blob the ExternalSecret injects as env (keys = env names):
#   printf '{"GOOGLE_CLIENT_SECRET":"<secret>","OIDC_CLIENT_ID":"<id>"}' | \
#     gcloud secrets versions add fairy-k8s01-janet-oauth \
#       --project=freckle-secrets-db8d4f --data-file=-
# OIDC_CLIENT_ID comes from `tofu output janet_oidc_client_id`.
resource "google_secret_manager_secret" "janet_oauth" {
  secret_id = "fairy-k8s01-janet-oauth"
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
