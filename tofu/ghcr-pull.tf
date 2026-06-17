# Cluster-wide GHCR image-pull credential for fairy-k8s01.
#
# A single GHCR Personal Access Token (nicolerenee, scope read:packages) — it
# can pull ANY private image that account can access, not just freckleapps. So
# distribution is opt-in: a ClusterExternalSecret only stamps the pull Secret
# into namespaces labeled `freckle.systems/ghcr-pull: "true"`
# (kubernetes/clusters/fairy-k8s01/apps/ghcr-pull). One token for the whole
# cluster — no per-namespace tokens. A dedicated PAT for fairy-k8s01, stored
# in GSM per the secrets-out-of-cluster migration.
#
# Tofu owns the secret EXISTENCE; the value is pushed by hand, never in state.
# Value is a JSON blob the ClusterExternalSecret template extracts:
#   printf '{"username":"nicolerenee","token":"<PAT>"}' | \
#     gcloud secrets versions add fairy-k8s01-ghcr-pull \
#       --project=freckle-secrets-db8d4f --data-file=-
resource "google_secret_manager_secret" "ghcr_pull" {
  secret_id = "fairy-k8s01-ghcr-pull"
  project   = local.project_id

  labels = {
    cluster  = "fairy-k8s01"
    consumer = "image-pull"
  }

  replication {
    auto {}
  }
}

# The fairy flux-system ESO SA (the cluster-wide ESO identity, also the
# serviceAccountRef of the GSM ClusterSecretStore gcp-sm-cluster) reads this
# one secret. Per-secret IAM — like flux-github-app — because the secret is
# cluster-scoped, not namespace-scoped, so the by-prefix eso-namespace grant
# doesn't apply.
resource "google_secret_manager_secret_iam_member" "ghcr_pull_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.ghcr_pull.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:flux-system:external-secrets-fairy-k8s01"
}
