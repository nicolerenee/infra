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

# APIs on the IaC project — needed because WIF, OIDC bucket, and the
# DRS-scoping tag/policy all live here.
resource "google_project_service" "iac_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "orgpolicy.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = local.iac_project
  service            = each.value
  disable_on_destroy = false
}

# OIDC hosting bucket lives in the IaC project (colocated with WIF).
resource "google_storage_bucket" "oidc" {
  name                        = local.oidc_bucket
  project                     = local.iac_project
  location                    = "US-CENTRAL1"
  uniform_bucket_level_access = true
  force_destroy               = false

  depends_on = [google_project_service.iac_apis]
}

resource "google_tags_tag_key" "public_jwks" {
  parent      = "projects/${local.iac_project}"
  short_name  = "public-jwks"
  description = "Marks resources that intentionally allow allUsers (e.g. JWKS bucket)"

  depends_on = [google_project_service.iac_apis]
}

resource "google_tags_tag_value" "public_jwks_true" {
  parent      = google_tags_tag_key.public_jwks.id
  short_name  = "true"
  description = "Public JWKS bucket exception"
}

resource "google_tags_location_tag_binding" "oidc_bucket" {
  parent    = "//storage.googleapis.com/projects/_/buckets/${google_storage_bucket.oidc.name}"
  tag_value = google_tags_tag_value.public_jwks_true.id
  location  = "us-central1"
}

resource "google_org_policy_policy" "drs_allow_tagged_jwks" {
  name   = "projects/${local.iac_project}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${local.iac_project}"

  spec {
    inherit_from_parent = true

    rules {
      allow_all = "TRUE"
      condition {
        title       = "Allow allUsers on tagged JWKS bucket"
        description = "Limits the DRS exception to GCS buckets carrying public-jwks=true"
        expression  = "resource.matchTag('${local.iac_project}/public-jwks', 'true')"
      }
    }
  }

  depends_on = [google_project_service.iac_apis]
}

resource "google_storage_bucket_iam_member" "oidc_public" {
  bucket = google_storage_bucket.oidc.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"

  depends_on = [
    google_tags_location_tag_binding.oidc_bucket,
    google_org_policy_policy.drs_allow_tagged_jwks,
  ]
}
