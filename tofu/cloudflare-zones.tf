# Look up the existing Cloudflare zone by name so we don't have to carry
# its ID around in env vars or hardcode it.
data "cloudflare_zones" "freckle_systems" {
  name = "freckle.systems"
}

# Manage the zone in tofu. The import block (below) adopts the existing
# zone on first apply by referencing the data-source-resolved ID.
resource "cloudflare_zone" "freckle_systems" {
  account = {
    id = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  }
  name = "freckle.systems"
  type = "full"

  lifecycle {
    # Zone-level settings (paused, dnssec, vanity NS, plan changes, etc.)
    # are managed in the Cloudflare dashboard — tofu just owns the
    # existence of the zone. Ignore drift on settings we don't manage.
    ignore_changes = [paused, vanity_name_servers, type]
  }
}

import {
  to = cloudflare_zone.freckle_systems
  id = data.cloudflare_zones.freckle_systems.result[0].id
}

# Additional zones tofu needs to know about (for scoped API token
# policies and per-zone records). Most are read-only data sources today;
# zones we actively manage records on get full resource ownership.
data "cloudflare_zones" "freckle_services" { name = "freckle.services" }
data "cloudflare_zones" "freckle_media" { name = "freckle.media" }
data "cloudflare_zones" "freckle_chat" { name = "freckle.chat" }
data "cloudflare_zones" "freckle_family" { name = "freckle.family" }

# freckle.id hosts only auth (pocket-id) and is the most sensitive zone
# we run. tofu owns the zone existence so it can't be moved/deleted
# out from under us; per-record management still happens externally.
data "cloudflare_zones" "freckle_id" {
  name = "freckle.id"
}

resource "cloudflare_zone" "freckle_id" {
  account = {
    id = data.google_secret_manager_secret_version.cloudflare_account_id.secret_data
  }
  name = "freckle.id"
  type = "full"

  lifecycle {
    ignore_changes = [paused, vanity_name_servers, type]
  }
}

import {
  to = cloudflare_zone.freckle_id
  id = data.cloudflare_zones.freckle_id.result[0].id
}

locals {
  # Per-cluster zone sets — used by token policies to grant access to
  # only the zones a given consumer actually needs. Listed by tofu
  # resource attribute (not raw data) so the dependency graph forces
  # zone existence before any token references it.
  cf_zone_ids = {
    freckle_systems  = cloudflare_zone.freckle_systems.id
    freckle_id       = cloudflare_zone.freckle_id.id
    freckle_services = data.cloudflare_zones.freckle_services.result[0].id
    freckle_media    = data.cloudflare_zones.freckle_media.result[0].id
    freckle_chat     = data.cloudflare_zones.freckle_chat.result[0].id
    freckle_family   = data.cloudflare_zones.freckle_family.result[0].id
  }
}
