provider "google" {
  # No default project — every resource sets its own. Setting one here
  # creates a cycle now that local.project_id derives from the
  # tofu-managed google_project.secrets resource.
  region                      = "us-central1"
  impersonate_service_account = "tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
}

provider "cloudflare" {
  # Token is fetched from Google Secret Manager (secret
  # `tofu-cloudflare-api-token` in the workload project) so no env var is
  # required. Bootstrap on first run:
  #
  #   gcloud secrets create tofu-cloudflare-api-token \
  #     --project=<secrets-project> --replication-policy=automatic
  #   printf '%s' "$YOUR_TOKEN" | gcloud secrets versions add \
  #     tofu-cloudflare-api-token --project=<secrets-project> --data-file=-
  #
  # Token scopes:
  #   Account > Workers R2 Storage:Edit
  #   Zone > DNS:Edit (for freckle.systems)
  api_token = data.google_secret_manager_secret_version.cloudflare_api_token.secret_data
}
