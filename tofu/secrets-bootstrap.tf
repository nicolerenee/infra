# Secrets that tofu itself reads at apply time for provider configuration
# (cross-provider auth that can't be sourced from the impersonated GCP SA).
#
# Values are populated manually with `gcloud secrets versions add` — never
# stored in tofu state. Tofu owns the secret resource (lifecycle, labels,
# IAM); content lifecycle stays outside tofu.

resource "google_secret_manager_secret" "tofu_cloudflare_api_token" {
  secret_id = "tofu-cloudflare-api-token"
  project   = local.project_id

  labels = {
    purpose = "tofu-runner-auth"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "tofu_cloudflare_account_id" {
  secret_id = "tofu-cloudflare-account-id"
  project   = local.project_id

  labels = {
    purpose = "tofu-runner-auth"
  }

  replication {
    auto {}
  }
}

# Read the latest version of the token for use in the cloudflare provider
# config below.
#
# Referenced by string ID (not via google_secret_manager_secret.id) so
# tofu doesn't defer the data source to apply time when the secret
# resource has pending changes — the provider config needs a concrete
# value at plan time.
data "google_secret_manager_secret_version" "cloudflare_api_token" {
  secret  = "tofu-cloudflare-api-token"
  project = local.project_id
}

data "google_secret_manager_secret_version" "cloudflare_account_id" {
  secret  = "tofu-cloudflare-account-id"
  project = local.project_id
}

# One-time import: the secret container must exist (with at least one
# version) before tofu plan can resolve the data source above. Bootstrap:
#
#   gcloud secrets create tofu-cloudflare-api-token \
#     --project=<secrets-project> --replication-policy=automatic
#   printf '%s' "$YOUR_TOKEN" | gcloud secrets versions add \
#     tofu-cloudflare-api-token --project=<secrets-project> --data-file=-
#
# After the first successful apply, this import block can be removed.
import {
  to = google_secret_manager_secret.tofu_cloudflare_api_token
  id = "${local.project_id}/tofu-cloudflare-api-token"
}

import {
  to = google_secret_manager_secret.tofu_cloudflare_account_id
  id = "${local.project_id}/tofu-cloudflare-account-id"
}
