provider "google" {
  # No default project — every resource sets its own. Setting one here
  # creates a cycle now that local.project_id derives from the
  # tofu-managed google_project.secrets resource.
  region                      = "us-central1"
  impersonate_service_account = "tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
}
