# Look up the existing Cloudflare zone by name so we don't have to carry
# its ID around in env vars or hardcode it.
data "cloudflare_zones" "freckle_systems" {
  name = "freckle.systems"
}

# Manage the zone in tofu. The import block (below) adopts the existing
# zone on first apply by referencing the data-source-resolved ID.
resource "cloudflare_zone" "freckle_systems" {
  account = {
    id = var.cloudflare_account_id
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
