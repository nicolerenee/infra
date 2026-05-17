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

# Per-cluster OIDC clients. Each cluster's app lives at a different
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
      display_name = "Grafana - Fairy"
      cluster      = "fairy-k8s01"
      namespace    = "observability"
      name         = "grafana-oidc" # GSM secret suffix
      hostname     = "grafana.fairy.freckle.systems"
      allowed_group_keys = [
        "grafana_admins",
        "grafana_users",
        "grafana_viewers",
      ]
    }
  }

  # Unique (cluster, namespace) pairs that need an ESO identity.
  oidc_namespaces = {
    for pair in distinct([
      for ck, cv in local.oidc_clients : {
        cluster   = cv.cluster
        namespace = cv.namespace
      }
    ]) : "${pair.cluster}-${pair.namespace}" => pair
  }
}

resource "pocketid_client" "consumer" {
  for_each = local.oidc_clients

  name = each.value.display_name
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

# GSM secret per client — JSON blob with client-id + client-secret so
# ESO `dataFrom.extract` lands both as separate k8s Secret keys directly.
# Naming follows `<cluster>-<namespace>-<name>` so the namespace-prefix
# IAM grant from `oidc_eso` below covers it.
module "oidc_client_secret" {
  source   = "./modules/gsm-secret"
  for_each = local.oidc_clients

  cluster             = each.value.cluster
  namespace           = each.value.namespace
  name                = each.value.name
  workload_project_id = local.project_id
  secret_data = jsonencode({
    "client-id"     = pocketid_client.consumer[each.key].id
    "client-secret" = pocketid_client.consumer[each.key].client_secret
  })
  extra_labels = {
    consumer = replace(each.key, "_", "-")
    purpose  = "oidc-client"
  }
}

# Project-level secretAccessor grant per (cluster, namespace). Same SA
# convention as CF tokens — `external-secrets-<cluster>` — so a single
# k8s SA in each namespace handles both CF tokens AND OIDC creds.
module "oidc_eso" {
  source   = "./modules/eso-namespace"
  for_each = local.oidc_namespaces

  cluster                 = each.value.cluster
  namespace               = each.value.namespace
  sa_name                 = "external-secrets-${each.value.cluster}"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}
