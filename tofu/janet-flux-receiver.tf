# HMAC token for the janet-manifests Flux image-scan Receiver on atlantis. The
# janet-brain publish workflow signs its webhook POST with this token and the
# notification-controller verifies it, forcing an immediate tag scan instead of
# the 5m ImageRepository poll. 32 random bytes (hex), no hand-entry — surfaced
# into flux-system by ESO (kubernetes/apps/flux/image-automation/
# receiver-janet-manifests.externalsecret.yaml).
#
# Flat secret + explicit per-secret accessor, mirroring flux-github-app.tf. The
# flux-system ESO reads GSM by per-secret IAM binding, NOT the gsm-secret
# module's `<cluster>-<namespace>-*` prefix scheme — there is no eso-namespace
# prefix grant for flux-system, so a module secret sync-errors on RBAC. The
# accessor is limited to ONLY the flux-system ESO SA on atlantis; combined with
# the namespace-scoped gcp-sm SecretStore, nothing outside flux-system can read it.
#
# The SAME value must be set as the FLUX_WEBHOOK_TOKEN GitHub Actions secret on
# freckleapps/janet-brain (no github provider in this tofu — manual). The
# FLUX_WEBHOOK_URL is the Receiver's runtime path:
# https://atlantis-k8s01-flux-webhook.<tailnet>/hook/<.status.webhookPath>.
resource "random_bytes" "janet_flux_receiver" {
  length = 32
}

resource "google_secret_manager_secret" "janet_flux_receiver" {
  secret_id = "flux-receiver-janet"
  project   = local.project_id

  labels = {
    consumer = "janet-brain"
    purpose  = "flux-image-receiver"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "janet_flux_receiver" {
  secret      = google_secret_manager_secret.janet_flux_receiver.id
  secret_data = random_bytes.janet_flux_receiver.hex
}

# Only the atlantis flux-system ESO SA may read it — the Receiver + janet-manifests
# ImageRepository both live in flux-system on atlantis. Scoped to that one SA.
resource "google_secret_manager_secret_iam_member" "janet_flux_receiver_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.janet_flux_receiver.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:flux-system:external-secrets-atlantis-k8s01"
}
