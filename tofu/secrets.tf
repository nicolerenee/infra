resource "google_secret_manager_secret" "this" {
  for_each = local.secrets

  secret_id = each.key
  project   = local.project_id

  labels = {
    cluster   = each.value.cluster
    namespace = each.value.namespace
  }

  replication {
    auto {}
  }
}
