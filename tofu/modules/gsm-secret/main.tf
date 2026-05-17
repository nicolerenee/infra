# A single GSM secret with one version. Naming follows the convention
# `<cluster>-<namespace>-<name>` so the namespace-prefix IAM grant from
# the `eso-namespace` module covers it without per-secret bindings.
resource "google_secret_manager_secret" "this" {
  secret_id = "${var.cluster}-${var.namespace}-${var.name}"
  project   = var.workload_project_id

  labels = merge(
    {
      cluster   = var.cluster
      namespace = var.namespace
    },
    var.extra_labels,
  )

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  secret      = google_secret_manager_secret.this.id
  secret_data = var.secret_data
}
