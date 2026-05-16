# APIs on the workload (secrets) project.
resource "google_project_service" "secrets_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

# APIs on the IaC project — needed for WIF pool/provider management +
# IAM credentials (the STS token exchange + generateIdToken calls go
# through these APIs).
resource "google_project_service" "iac_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = local.iac_project
  service            = each.value
  disable_on_destroy = false
}
