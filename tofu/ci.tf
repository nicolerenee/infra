# GitHub Actions auth via Workload Identity Federation. The workflow
# exchanges the action-run's OIDC token for a Google access token
# representing the tofu-runner SA, then tofu proceeds exactly like local
# dev.

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Pool for GitHub Actions OIDC identities used by CI/CD workflows"
  project                   = local.iac_project

  depends_on = [google_project_service.iac_apis]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"
  project                            = local.iac_project

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.actor"            = "assertion.actor"
    "attribute.ref"              = "assertion.ref"
    "attribute.event_name"       = "assertion.event_name"
  }

  # Restrict to this repo. Loosen later if other repos need access.
  attribute_condition = "assertion.repository == 'nicolerenee/infra'"
}

# Allow workflows from nicolerenee/infra to impersonate tofu-runner. Scoped
# by repository (any branch); the workflow's trigger conditions gate which
# actions get to run (PR=plan, push-to-main=apply).
resource "google_service_account_iam_member" "tofu_runner_github_actions" {
  service_account_id = "projects/${local.iac_project}/serviceAccounts/tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/github-actions/attribute.repository/nicolerenee/infra"
}

# Allow tofu-runner to impersonate itself, so the google provider's
# impersonate_service_account=tofu-runner works in CI (where ADC is
# already tofu-runner) without needing two different provider configs.
resource "google_service_account_iam_member" "tofu_runner_self_impersonate" {
  service_account_id = "projects/${local.iac_project}/serviceAccounts/tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:tofu-runner@${local.iac_project}.iam.gserviceaccount.com"
}
