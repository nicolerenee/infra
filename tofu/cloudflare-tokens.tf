# Per-consumer Cloudflare API tokens. Replaces the single broadly-scoped
# token that was copypasta'd across cert-manager + external-dns + offsite
# hosts. Each token here is:
#   - Scoped to the minimum zones the consumer touches
#   - Granted only the permissions it needs (DNS:Edit, optionally Zone:Read)
#   - Auto-rotated by tofu on an 80-day cadence (`time_rotating` keeper
#     fires `replace_triggered_by`, which destroys the old token and
#     mints a new one — `create_before_destroy` keeps GSM populated
#     during the brief overlap)
#   - Hard-expiring at rotation+90d (Cloudflare enforces; if rotation
#     doesn't fire in time, consumer breaks → forcing function to apply)
#
# Token value flows into GSM (one secret per token) → ESO+WIF pulls into
# k8s Secret in the consumer's namespace. The IAM bindings below grant
# secretAccessor only on the relevant `<cluster>-<ns>-` prefix to the
# cluster-specific federated principal, so a fairy compromise can't read
# atlantis tokens.

# Single shared rotation timer — when 80 days elapse since last rotation,
# all tokens get replaced together. Simpler than per-token timers and
# means rotation is one apply.
resource "time_rotating" "cf_token_rotation" {
  rotation_days = 80
}

# Well-known Cloudflare API token permission group IDs (zone-level).
# Stable across all CF accounts.
locals {
  cf_perm_dns_write = "4755a26eedb94da69e1066d98aa820be" # Zone > DNS > Edit
  cf_perm_zone_read = "c8fed203ed3043cba015a93ad1616f1f" # Zone > Zone > Read

  # Hard token expiry — 90d from the last rotation. Gives a 10-day
  # safety buffer between the rotation cadence (80d) and the hard wall
  # CF will enforce; if `tofu apply` slips past the 80d mark, the
  # consumer keeps working for 10 more days before tokens actually die.
  cf_token_expires_on = timeadd(time_rotating.cf_token_rotation.rotation_rfc3339, "240h")

  # Per-token zone scopes. Listed by short key into local.cf_zone_ids.
  cf_token_scopes = {
    cert_manager_fairy = {
      zones       = ["freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write"]
    }
    cert_manager_atlantis = {
      zones       = ["freckle_id", "freckle_chat", "freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write"]
    }
    external_dns_fairy_cloudflare = {
      zones       = ["freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write", "zone_read"]
    }
    external_dns_fairy_cloudflare_tunnel = {
      zones       = ["freckle_systems", "freckle_services", "freckle_family"]
      permissions = ["dns_write", "zone_read"]
    }
    external_dns_atlantis_cloudflare = {
      zones       = ["freckle_chat", "freckle_family", "freckle_id", "freckle_media", "freckle_services", "freckle_systems"]
      permissions = ["dns_write", "zone_read"]
    }
  }

  # Which (cluster, namespace, GSM secret name) each token maps to. The
  # GSM secret name encodes the cluster + namespace + consumer; the IAM
  # binding below uses that prefix to enforce per-cluster isolation.
  cf_token_consumers = {
    cert_manager_fairy = {
      cluster    = "fairy-k8s01"
      namespace  = "cert-manager"
      gsm_secret = "fairy-k8s01-cert-manager-cloudflare-token"
    }
    cert_manager_atlantis = {
      cluster    = "atlantis-k8s01"
      namespace  = "cert-manager"
      gsm_secret = "atlantis-k8s01-cert-manager-cloudflare-token"
    }
    external_dns_fairy_cloudflare = {
      cluster    = "fairy-k8s01"
      namespace  = "external-dns"
      gsm_secret = "fairy-k8s01-external-dns-cloudflare-token"
    }
    external_dns_fairy_cloudflare_tunnel = {
      cluster    = "fairy-k8s01"
      namespace  = "external-dns"
      gsm_secret = "fairy-k8s01-external-dns-cloudflare-tunnel-token"
    }
    external_dns_atlantis_cloudflare = {
      cluster    = "atlantis-k8s01"
      namespace  = "external-dns"
      gsm_secret = "atlantis-k8s01-external-dns-cloudflare-token"
    }
  }
}

# The token resources themselves. Account-scoped (not user-scoped) so
# rotation/management goes through the account's API tokens endpoint —
# the tofu CF API token authenticates at the account level too.
resource "cloudflare_account_token" "consumer" {
  for_each = local.cf_token_scopes

  account_id = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data

  name = "${replace(each.key, "_", "-")}-${formatdate("YYYYMMDD", time_rotating.cf_token_rotation.rotation_rfc3339)}"

  policies = [{
    effect = "allow"
    permission_groups = [
      for p in each.value.permissions : {
        id = lookup({
          dns_write = local.cf_perm_dns_write
          zone_read = local.cf_perm_zone_read
        }, p)
      }
    ]
    # v5 of the CF provider encodes the resources map as a JSON string,
    # not a native map. Hence the jsonencode wrapper.
    resources = jsonencode({
      for z in each.value.zones :
      "com.cloudflare.api.account.zone.${local.cf_zone_ids[z]}" => "*"
    })
  }]

  expires_on = local.cf_token_expires_on

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      time_rotating.cf_token_rotation,
    ]
  }
}

# GSM secret + version for each token. Per-cluster, per-namespace prefix
# so IAM conditions can scope access tightly.
resource "google_secret_manager_secret" "cf_token" {
  for_each = local.cf_token_consumers

  secret_id = each.value.gsm_secret
  project   = local.project_id

  labels = {
    cluster   = each.value.cluster
    namespace = each.value.namespace
    consumer  = replace(each.key, "_", "-")
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cf_token" {
  for_each = local.cf_token_consumers

  secret      = google_secret_manager_secret.cf_token[each.key].id
  secret_data = cloudflare_account_token.consumer[each.key].value
}

# IAM bindings. One per (cluster, namespace) pair, with the SA name set
# to `external-secrets-<cluster-short>` so each cluster gets its own
# federated principal subject. The condition limits which secrets each
# principal can read — only the ones starting with the cluster + namespace
# prefix.
locals {
  # Unique (cluster, namespace) pairs we need IAM bindings for. SA name
  # uses the FULL cluster name (`external-secrets-<cluster>`) so each
  # cluster's federated principal is distinct — including when multiple
  # clusters in the same series coexist (e.g., atlantis-k8s01 vs
  # atlantis-k8s02 during a rolling cluster replacement).
  # Built via distinct() because multiple token consumers can share the
  # same (cluster, namespace) — external-dns has cloudflare and
  # cloudflare-tunnel both in fairy-k8s01/external-dns.
  cf_token_iam_bindings = {
    for pair in distinct([
      for ck, cv in local.cf_token_consumers : {
        cluster   = cv.cluster
        namespace = cv.namespace
      }
    ]) : "${pair.cluster}-${pair.namespace}" => pair
  }
}

resource "google_project_iam_member" "cf_token_eso_accessor" {
  for_each = local.cf_token_iam_bindings

  project = local.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "principal://iam.googleapis.com/projects/${data.google_project.iac.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.clusters.workload_identity_pool_id}/subject/system:serviceaccount:${each.value.namespace}:external-secrets-${each.value.cluster}"

  condition {
    title       = "${each.value.cluster}-${each.value.namespace}-tokens"
    description = "ESO in ${each.value.cluster}/${each.value.namespace} reads ${each.value.cluster}-${each.value.namespace}-* CF token secrets"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/${each.value.cluster}-${each.value.namespace}-\")"
  }
}
