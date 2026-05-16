resource "google_service_account" "eso" {
  for_each = local.namespace_bindings

  account_id   = lookup(each.value, "gcp_sa_id", "${each.value.cluster}-${each.value.namespace}")
  display_name = "ESO / ${each.value.cluster} / ${each.value.namespace}"
  project      = local.project_id
}

resource "google_service_account_iam_member" "eso_wif" {
  for_each = local.namespace_bindings

  service_account_id = google_service_account.eso[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:${each.value.namespace}:${each.value.k8s_sa}"
}

resource "google_project_iam_member" "eso_secret_accessor" {
  for_each = local.namespace_bindings

  project = local.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso[each.key].email}"

  condition {
    title       = "${each.value.cluster}-${each.value.namespace}-ns"
    description = "Limit ESO SA to its own cluster+namespace secrets by name prefix"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/${each.value.cluster}-${each.value.namespace}-\")"
  }
}
