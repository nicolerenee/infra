# Project-level secretAccessor grant for one (cluster, namespace) ESO
# identity. The IAM condition narrows access to GSM secrets whose name
# starts with `<cluster>-<namespace>-`, so a single grant covers every
# secret the namespace owns without re-binding per-secret.
#
# Companion module `gsm-secret` produces secret IDs that match this
# prefix naturally — call `gsm-secret` with the same cluster+namespace
# and any name, and access is granted by this module's binding.
resource "google_project_iam_member" "accessor" {
  project = var.workload_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "principal://iam.googleapis.com/projects/${var.iac_project_number}/locations/global/workloadIdentityPools/${var.wif_pool_id}/subject/system:serviceaccount:${var.namespace}:${var.sa_name}"

  condition {
    title       = "${var.cluster}-${var.namespace}-ns"
    description = "Limit ESO SA to its own cluster+namespace secrets by name prefix"
    expression  = "resource.name.startsWith(\"projects/${var.workload_project_number}/secrets/${var.cluster}-${var.namespace}-\")"
  }
}
