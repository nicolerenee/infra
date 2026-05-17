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

  # Per-token config. One entry per Cloudflare API token we mint:
  #   - where it lands (cluster, namespace, name → GSM secret_id suffix)
  #   - what it can do (zones, permissions)
  #
  # The gsm-secret module composes the secret_id as
  # `<cluster>-<namespace>-<name>` — same prefix the eso-namespace IAM
  # grant scopes access to.
  cf_tokens = {
    cert_manager_fairy = {
      cluster     = "fairy-k8s01"
      namespace   = "cert-manager"
      name        = "cloudflare-token"
      zones       = ["freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write"]
    }
    cert_manager_atlantis = {
      cluster     = "atlantis-k8s01"
      namespace   = "cert-manager"
      name        = "cloudflare-token"
      zones       = ["freckle_id", "freckle_chat", "freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write"]
    }
    external_dns_fairy_cloudflare = {
      cluster     = "fairy-k8s01"
      namespace   = "external-dns"
      name        = "cloudflare-token"
      zones       = ["freckle_systems", "freckle_services", "freckle_media"]
      permissions = ["dns_write", "zone_read"]
    }
    external_dns_fairy_cloudflare_tunnel = {
      cluster     = "fairy-k8s01"
      namespace   = "external-dns"
      name        = "cloudflare-tunnel-token"
      zones       = ["freckle_systems", "freckle_services", "freckle_family"]
      permissions = ["dns_write", "zone_read"]
    }
    external_dns_atlantis_cloudflare = {
      cluster     = "atlantis-k8s01"
      namespace   = "external-dns"
      name        = "cloudflare-token"
      zones       = ["freckle_chat", "freckle_family", "freckle_id", "freckle_media", "freckle_services", "freckle_systems"]
      permissions = ["dns_write", "zone_read"]
    }
  }

  # Unique (cluster, namespace) pairs that need an ESO identity. Distinct
  # because external-dns has two token consumers but only one ns.
  cf_token_namespaces = {
    for pair in distinct([
      for ck, cv in local.cf_tokens : {
        cluster   = cv.cluster
        namespace = cv.namespace
      }
    ]) : "${pair.cluster}-${pair.namespace}" => pair
  }
}

# The token resources themselves. Account-scoped (not user-scoped) so
# rotation/management goes through the account's API tokens endpoint —
# the tofu CF API token authenticates at the account level too.
resource "cloudflare_account_token" "consumer" {
  for_each = local.cf_tokens

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

# Per-token GSM secret + version via the gsm-secret module. Secret_id is
# composed as `<cluster>-<namespace>-<name>` — matches the namespace
# prefix the eso-namespace module below grants access to.
module "cf_token_secret" {
  source   = "./modules/gsm-secret"
  for_each = local.cf_tokens

  cluster             = each.value.cluster
  namespace           = each.value.namespace
  name                = each.value.name
  secret_data         = cloudflare_account_token.consumer[each.key].value
  workload_project_id = local.project_id
  extra_labels = {
    consumer = replace(each.key, "_", "-")
  }
}

# Project-level secretAccessor grant per (cluster, namespace). One IAM
# binding covers every token in the namespace, since they all share the
# `<cluster>-<namespace>-` prefix.
module "cf_token_eso" {
  source   = "./modules/eso-namespace"
  for_each = local.cf_token_namespaces

  cluster                 = each.value.cluster
  namespace               = each.value.namespace
  sa_name                 = "external-secrets-${each.value.cluster}"
  workload_project_id     = local.project_id
  workload_project_number = data.google_project.this.number
  iac_project_number      = data.google_project.iac.number
  wif_pool_id             = google_iam_workload_identity_pool.clusters.workload_identity_pool_id
}

# Note: no `moved {}` blocks here. The old resources used for_each on
# the resource itself; the new structure has for_each on the module
# wrapper with a non-iterated child resource inside. OpenTofu can't
# auto-map between those two address shapes. Tofu will destroy + create
# all 14 resources. Safe because:
#   - CF token values come from `cloudflare_account_token.consumer[].value`
#     (in state, unchanged), so recreated GSM secrets get the same data
#   - ESO caches the latest secret value in the k8s Secret; the brief
#     window during destroy+create is invisible to consumers until the
#     next refresh, which finds the recreated GSM secret + binding
