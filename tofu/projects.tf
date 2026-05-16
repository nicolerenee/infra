data "google_organization" "this" {
  domain = "freckle.family"
}

# Suffix is generated once and locked in state. Don't regenerate — that
# would force a project replacement (and a 30-day soft-delete on the
# old one).
resource "random_id" "secrets_project_suffix" {
  byte_length = 3
  keepers     = { name = "freckle-secrets" }
}

resource "google_project" "secrets" {
  name       = "Freckle Secrets"
  project_id = "freckle-secrets-${random_id.secrets_project_suffix.hex}"
  org_id     = data.google_organization.this.org_id

  # Inherit billing from the IaC project — same billing account fronts
  # all freckle.* projects, so no separate variable/secret needed.
  billing_account = data.google_project.iac.billing_account

  auto_create_network = false

  lifecycle {
    prevent_destroy = true
  }
}
