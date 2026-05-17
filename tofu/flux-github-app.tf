# Shared GSM secret holding the GitHub App credential Flux uses for repo
# sync (source-controller) and write-back commits (image-automation-
# controller). One credential, every cluster reads it. Replaces the 1P-
# backed bootstrap path so the operator only needs gcloud, not also 1P.
#
# Secret value is a JSON blob with three keys matching what the shared
# ExternalSecret template expects:
#   {"GITHUB_APP_ID": "...",
#    "GITHUB_INSTALLATION_ID": "...",
#    "GITHUB_PRIVATE_KEY": "..."}
#
# Tofu owns the secret EXISTENCE; the value is pushed by hand (one-time)
# from 1P. See bootstrap docs for the op→gcloud command.

resource "google_secret_manager_secret" "flux_github_app" {
  secret_id = "flux-github-app"
  project   = local.project_id

  labels = {
    consumer = "flux"
    purpose  = "github-app"
  }

  replication {
    auto {}
  }
}

# Per-cluster IAM bindings. Each cluster's flux-system ESO SA gets read
# access to this one shared secret. Per-secret IAM (vs project + condition)
# because the secret is shared across clusters — the by-prefix scheme used
# for the per-cluster CF tokens doesn't fit here.
resource "google_secret_manager_secret_iam_member" "flux_github_app_accessor" {
  for_each = toset(keys(var.clusters))

  project   = local.project_id
  secret_id = google_secret_manager_secret.flux_github_app.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:flux-system:external-secrets-${each.key}"
}
