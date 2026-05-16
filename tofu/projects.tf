data "google_organization" "this" {
  domain = "freckle.family"
}

variable "billing_account" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX) to associate with managed projects. Set via TF_VAR_billing_account."
  type        = string
}

# Suffix is generated once and locked in state. Don't regenerate — that
# would force a project replacement (and a 30-day soft-delete on the
# old one).
resource "random_id" "secrets_project_suffix" {
  byte_length = 3
  keepers     = { name = "freckle-secrets" }
}

resource "google_project" "secrets" {
  name            = "Freckle Secrets"
  project_id      = "freckle-secrets-${random_id.secrets_project_suffix.hex}"
  org_id          = data.google_organization.this.org_id
  billing_account = var.billing_account

  auto_create_network = false

  lifecycle {
    prevent_destroy = true
  }
}
