# Dedicated Postgres (CNPG) for the Janet brain — its own cluster, not the
# shared pg-17a (which is for smaller services). Modeled on hedgehog's db, but
# secrets live in GSM with tofu-GENERATED passwords (no hand-entry): tofu mints
# them, stores them via the gsm-secret module, ESO syncs them into the janet ns.
# Covered by the fairy-k8s01-janet-* accessor grant (tofu/janet.tf).
#
# alnum-only (special=false) so the password is safe inside the DATABASE_URL
# without percent-encoding.
resource "random_password" "janet_db_super" {
  length  = 32
  special = false
}

resource "random_password" "janet_db_app" {
  length  = 32
  special = false
}

# Superuser secret for the CNPG Cluster (superuserSecret). Keys match what the
# janet-db-secrets ExternalSecret template expects.
module "janet_db_superuser" {
  source = "./modules/gsm-secret"

  cluster     = "fairy-k8s01"
  namespace   = "janet"
  name        = "db-superuser"
  secret_data = jsonencode({ POSTGRES_SUPER_USER = "postgres", POSTGRES_SUPER_PASS = random_password.janet_db_super.result })

  workload_project_id = local.project_id
  extra_labels        = { consumer = "janet-db" }
}

# App-role secret: consumed by the Cluster's managed.roles block AND by the
# brain's DATABASE_URL ExternalSecret.
module "janet_db_app" {
  source = "./modules/gsm-secret"

  cluster     = "fairy-k8s01"
  namespace   = "janet"
  name        = "db-app"
  secret_data = jsonencode({ username = "janet", password = random_password.janet_db_app.result })

  workload_project_id = local.project_id
  extra_labels        = { consumer = "janet-db" }
}
