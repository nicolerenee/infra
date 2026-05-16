resource "google_iam_workload_identity_pool" "clusters" {
  workload_identity_pool_id = local.wif_pool_id
  display_name              = "Kubernetes clusters"
  description               = "Pool for k8s clusters using WIF to access GCP resources"
  project                   = local.iac_project

  depends_on = [google_project_service.iac_apis]
}

resource "google_iam_workload_identity_pool_provider" "cluster" {
  for_each = local.clusters

  project                            = local.iac_project
  workload_identity_pool_id          = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
  workload_identity_pool_provider_id = each.key
  display_name                       = each.key

  oidc {
    issuer_uri = "https://storage.googleapis.com/${google_storage_bucket.oidc.name}/${each.key}"
  }

  attribute_mapping = {
    "google.subject"      = "assertion.sub"
    "attribute.namespace" = "assertion['kubernetes.io']['namespace']"
    "attribute.k8s_sa"    = "assertion['kubernetes.io']['serviceaccount']['name']"
  }

  attribute_condition = "assertion['kubernetes.io']['namespace'] != ''"
}
