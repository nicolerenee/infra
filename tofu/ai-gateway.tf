# Internal Envoy AI Gateway (inference ns) credentials.
#
# The gateway terminates the brain's native Anthropic Messages traffic and
# forwards it to api.anthropic.com using this key. The key lives in GSM and
# is pulled into the cluster by ESO in the inference namespace via the
# namespace-prefix accessor grant below — part of the ongoing migration of
# k8s secrets out of 1Password onto Google Secret Manager.
#
# Tofu owns the secret EXISTENCE (container + IAM); the value is pushed by
# hand, never stored in tofu state. After `tofu apply` creates the
# container, set the value once:
#
#   printf '%s' "$ANTHROPIC_API_KEY" | gcloud secrets versions add \
#     fairy-k8s01-inference-anthropic-api-key \
#     --project=freckle-secrets-db8d4f --data-file=-
#
# Rotate by adding a new version the same way; ESO picks it up on refresh.
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "fairy-k8s01-inference-anthropic-api-key"
  project   = local.project_id

  labels = {
    cluster   = "fairy-k8s01"
    namespace = "inference"
    consumer  = "envoy-ai-gateway"
  }

  replication {
    auto {}
  }
}

# Project-level secretAccessor grant for the inference ns ESO identity.
# Single binding covers every secret in `fairy-k8s01-inference-*`,
# including the Anthropic key above.
module "inference_eso" {
  source = "./modules/eso-namespace"

  cluster                 = "fairy-k8s01"
  namespace               = "inference"
  sa_name                 = "external-secrets-inference"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}
