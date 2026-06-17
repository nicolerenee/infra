# Google Workspace MCP server (janet-mcp namespace) — GitOps'd from the old
# manual kubectl-apply. Its own namespace keeps the egress boundary: only the
# MCP server reaches Google; the brain talks only to it.
#
# Secret: the Google OAuth client id (non-secret, but kept out of this public
# repo) + a JWT signing key the server uses for its own session tokens. Both
# are externally sourced, so tofu owns only the container; push the value once
# (the client id is the same one Janet uses; generate the JWT key):
#   printf '{"GOOGLE_OAUTH_CLIENT_ID":"<client-id>","FASTMCP_SERVER_AUTH_GOOGLE_JWT_SIGNING_KEY":"'"$(openssl rand -hex 32)"'"}' | \
#     gcloud secrets versions add fairy-k8s01-janet-mcp-auth \
#       --project=freckle-secrets-db8d4f --data-file=-
resource "google_secret_manager_secret" "janet_mcp_auth" {
  secret_id = "fairy-k8s01-janet-mcp-auth"
  project   = local.project_id

  labels = {
    cluster   = "fairy-k8s01"
    namespace = "janet-mcp"
    consumer  = "google-workspace-mcp"
  }

  replication {
    auto {}
  }
}

# secretAccessor grant for the janet-mcp ns ESO identity — covers
# fairy-k8s01-janet-mcp-*.
module "janet_mcp_eso" {
  source = "./modules/eso-namespace"

  cluster                 = "fairy-k8s01"
  namespace               = "janet-mcp"
  sa_name                 = "external-secrets-janet-mcp"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}
