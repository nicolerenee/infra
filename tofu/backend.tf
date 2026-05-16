terraform {
  backend "gcs" {
    # State bucket lives in the dedicated IaC admin project, not in any
    # of the workload projects this tofu tree manages.
    bucket = "freckle-iac-438712-tofu-state"
    prefix = "freckle-secrets"

    # User runs tofu as themselves but impersonates the runner SA, so
    # their account only needs serviceAccountTokenCreator on the SA.
    impersonate_service_account = "tofu-runner@freckle-iac-438712.iam.gserviceaccount.com"
  }
}
