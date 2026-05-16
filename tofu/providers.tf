provider "google" {
  # No default project — every resource sets its own. Setting one here
  # creates a cycle now that local.project_id derives from the
  # tofu-managed google_project.secrets resource.
  region                      = "us-central1"
  impersonate_service_account = "tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
}

provider "cloudflare" {
  # Reads CLOUDFLARE_API_TOKEN from the environment.
  # Create a scoped token in the Cloudflare dashboard with permissions:
  #   Account > Workers R2 Storage:Edit
  #   Zone > DNS:Edit (for freckle.systems)
}
