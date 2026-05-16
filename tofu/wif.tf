resource "google_iam_workload_identity_pool" "clusters" {
  workload_identity_pool_id = local.wif_pool_id
  display_name              = "Kubernetes clusters"
  description               = "Pool for k8s clusters using WIF to access GCP resources"
  project                   = local.iac_project

  depends_on = [google_project_service.iac_apis]
}

# One provider per cluster. issuer_uri + jwks_json come from var.clusters
# (populated by `task wif:bootstrap CLUSTER=<name>`). Inline jwks_json
# means GCP STS never tries to fetch the cluster's discovery endpoint —
# the cluster API server can stay fully internal.
resource "google_iam_workload_identity_pool_provider" "cluster" {
  for_each = var.clusters

  project                            = local.iac_project
  workload_identity_pool_id          = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
  workload_identity_pool_provider_id = each.key
  display_name                       = each.key

  oidc {
    issuer_uri = each.value.issuer_uri
    jwks_json  = each.value.jwks_json
  }

  attribute_mapping = {
    "google.subject"      = "assertion.sub"
    "attribute.namespace" = "assertion['kubernetes.io']['namespace']"
    "attribute.k8s_sa"    = "assertion['kubernetes.io']['serviceaccount']['name']"
  }

  attribute_condition = "assertion['kubernetes.io']['namespace'] != ''"
}
