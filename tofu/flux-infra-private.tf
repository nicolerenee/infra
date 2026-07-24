# SSH deploy key for the second Flux source: freckleapps/infra (private).
# atlantis-k8s01 syncs that repo as the `infra-private` GitRepository, in
# addition to this public repo (the primary flux-system source). Business-
# sensitive workloads (WHMCS, etc.) live there.
#
# Read-only deploy key, generated out-of-band (ssh-keygen), NOT by tofu — the
# private key never enters tofu state. Tofu owns the secret EXISTENCE and the
# IAM grant only; the value is pushed by hand, exactly like flux-github-app.tf.
# Secret value is a JSON blob shaped for the ExternalSecret template in
# kubernetes/apps/flux/instance/infra-private-source.externalsecret.yaml:
#   {"identity": "<ed25519 private key PEM>",
#    "known_hosts": "github.com ssh-ed25519 AAAA..."}
#
# The matching PUBLIC key is registered as a read-only deploy key on
# freckleapps/infra (done via gh, one-time — no github provider in this tofu).
resource "google_secret_manager_secret" "flux_infra_private_deploy_key" {
  secret_id = "atlantis-k8s01-flux-infra-private-deploy-key"
  project   = local.project_id

  labels = {
    cluster  = "atlantis-k8s01"
    consumer = "flux"
    purpose  = "git-deploy-key"
  }

  replication {
    auto {}
  }
}

# Only the atlantis flux-system ESO SA may read it. Per-secret binding
# mirroring flux-github-app.tf / janet-flux-receiver.tf — flux-system reads GSM
# by explicit per-secret IAM, not the `<cluster>-<namespace>-*` prefix scheme
# (there is no eso-namespace prefix grant for flux-system). Combined with the
# namespace-scoped gcp-sm SecretStore, nothing outside flux-system can read it.
resource "google_secret_manager_secret_iam_member" "flux_infra_private_deploy_key_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.flux_infra_private_deploy_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:flux-system:external-secrets-atlantis-k8s01"
}
