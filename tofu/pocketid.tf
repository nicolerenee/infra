# pocket-id OIDC clients managed declaratively. Each consumer (grafana,
# alertmanager, future apps) gets its own client with scoped redirect
# URIs. tofu creates the client via the pocket-id API; the resulting
# client_id + client_secret get pushed into GSM keyed by
# `<cluster>-<ns>-<app>-oidc`, and the consumer's namespace ESO reads
# it through the same per-cluster IAM pattern we use for CF tokens.
#
# Bootstrap: pocket-id admin API key must exist in GSM as
# `tofu-pocketid-api-token` before this provider initializes. One-time
# operator step:
#   1. Generate API key in pocket-id admin UI
#   2. printf '%s' "$KEY" | gcloud secrets versions add tofu-pocketid-api-token \
#        --project=freckle-secrets-db8d4f --data-file=-

data "google_secret_manager_secret_version" "pocketid_api_token" {
  secret  = "tofu-pocketid-api-token"
  project = local.project_id
}

provider "pocketid" {
  base_url  = "https://freckle.id"
  api_token = data.google_secret_manager_secret_version.pocketid_api_token.secret_data
}

# Shared user groups across OIDC consumers. Created once in pocket-id;
# each client's `allowed_user_groups` references the IDs. Logo upload
# (per group / per client) still happens in the pocket-id admin UI —
# the provider exposes no logo-upload attribute.
locals {
  oidc_groups = {
    grafana_admins  = { friendly_name = "Grafana Admins" }
    grafana_users   = { friendly_name = "Grafana Users" }
    grafana_viewers = { friendly_name = "Grafana Viewers" }
  }
}

resource "pocketid_group" "groups" {
  for_each      = local.oidc_groups
  name          = each.key
  friendly_name = each.value.friendly_name
}

# Groups already exist in pocket-id (manually created); adopt them by
# name so apply doesn't fail with "already exists".
data "pocketid_group" "existing" {
  for_each = local.oidc_groups
  name     = each.key
}

import {
  for_each = local.oidc_groups
  to       = pocketid_group.groups[each.key]
  id       = data.pocketid_group.existing[each.key].id
}

# Per-cluster OIDC clients. Each cluster's grafana lives at a different
# hostname, so they need distinct clients (callback URLs are part of
# the client config and can't be wildcarded for security).
#
# Atlantis grafana is currently using a hand-managed client in pocket-id
# (created in the UI). To bring it under tofu, add a `grafana_atlantis`
# entry here AND a tofu `import` block referencing its existing client
# ID — otherwise apply would create a duplicate. Phasing fairy first
# so the new flow gets exercised before touching the live atlantis
# instance.
locals {
  oidc_clients = {
    grafana_fairy = {
      name      = "Grafana - Fairy"
      cluster   = "fairy-k8s01"
      namespace = "observability"
      app       = "grafana"
      hostname  = "grafana.fairy.freckle.systems"
      allowed_group_keys = [
        "grafana_admins",
        "grafana_users",
        "grafana_viewers",
      ]
    }
  }
}

resource "pocketid_client" "consumer" {
  for_each = local.oidc_clients

  name = each.value.name
  callback_urls = [
    "https://${each.value.hostname}/login/generic_oauth",
  ]
  launch_url   = "https://${each.value.hostname}"
  is_public    = false
  pkce_enabled = true
  allowed_user_groups = [
    for g in each.value.allowed_group_keys :
    pocketid_group.groups[g].id
  ]
}

# GSM secret per client — JSON blob with client_id + client_secret so
# ESO `dataFrom.extract` can pull both into a single k8s Secret.
resource "google_secret_manager_secret" "oidc_client" {
  for_each = local.oidc_clients

  secret_id = "${each.value.cluster}-${each.value.namespace}-${each.value.app}-oidc"
  project   = local.project_id

  labels = {
    cluster   = each.value.cluster
    namespace = each.value.namespace
    consumer  = each.value.app
    purpose   = "oidc-client"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "oidc_client" {
  for_each = local.oidc_clients

  secret = google_secret_manager_secret.oidc_client[each.key].id
  # Key names match what the consumer's ExternalSecret expects directly
  # via `dataFrom.extract` (no template remap needed). Grafana CRD's
  # AUTH_CLIENT_ID / AUTH_CLIENT_SECRET env vars read from these keys.
  secret_data = jsonencode({
    "client-id"     = pocketid_client.consumer[each.key].id
    "client-secret" = pocketid_client.consumer[each.key].client_secret
  })
}

# IAM: each consumer's namespace ESO SA can read its own OIDC secret.
# Reuses the per-cluster `external-secrets-<cluster>` SA naming from
# the CF-token migration — same SA serves CF tokens AND OIDC creds in
# a namespace, just on different GSM secret prefixes.
locals {
  oidc_iam_bindings = {
    for pair in distinct([
      for ck, cv in local.oidc_clients : {
        cluster   = cv.cluster
        namespace = cv.namespace
      }
    ]) : "${pair.cluster}-${pair.namespace}" => pair
  }
}

resource "google_project_iam_member" "oidc_eso_accessor" {
  for_each = local.oidc_iam_bindings

  project = local.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:${each.value.namespace}:external-secrets-${each.value.cluster}"

  condition {
    title       = "${each.value.cluster}-${each.value.namespace}-oidc"
    description = "ESO in ${each.value.cluster}/${each.value.namespace} reads ${each.value.cluster}-${each.value.namespace}-*-oidc secrets"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/${each.value.cluster}-${each.value.namespace}-\") && resource.name.endsWith(\"-oidc\")"
  }
}
