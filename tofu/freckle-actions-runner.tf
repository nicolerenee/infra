# GitHub App credential for the freckle-actions runner scale set on
# atlantis-k8s01. The runner is an org-level ARC scale set for the
# freckleapps GitHub org, so this credential is a GitHub App installed
# on `freckleapps` with read:org + repo + actions:read scopes.
#
# Tofu owns the secret EXISTENCE and the IAM grant. Value is pushed
# manually after creating the GitHub App (see operator runbook). Secret
# value is a JSON blob shaped for ESO `dataFrom.extract`:
#   {"github_app_id": "...",
#    "github_app_installation_id": "...",
#    "github_app_private_key": "..."}
#
# Name follows `<cluster>-<namespace>-<consumer>` so the namespace IAM
# grant in `freckle_actions_eso` covers it via the prefix condition.

resource "google_secret_manager_secret" "freckle_actions_runner_github_app" {
  secret_id = "atlantis-k8s01-freckle-actions-runner-github-app"
  project   = local.project_id

  labels = {
    cluster  = "atlantis-k8s01"
    consumer = "freckle-actions-runner"
    purpose  = "github-app"
  }

  replication {
    auto {}
  }
}

# Per-namespace secretAccessor grant for the ESO identity in
# freckle-actions on atlantis-k8s01. Single binding covers every secret
# in `atlantis-k8s01-freckle-actions-*` via the prefix condition.
module "freckle_actions_eso" {
  source = "./modules/eso-namespace"

  cluster                 = "atlantis-k8s01"
  namespace               = "freckle-actions"
  sa_name                 = "external-secrets-atlantis-k8s01"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}
