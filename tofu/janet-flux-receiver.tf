# HMAC token for the janet-manifests Flux image-scan Receiver on atlantis. The
# janet-brain publish workflow signs its webhook POST with this token and the
# notification-controller verifies it, so a push forces an immediate tag scan
# instead of waiting for the 5m ImageRepository poll. 32 random bytes (hex),
# no hand-entry — stored in GSM and surfaced into flux-system by ESO via the
# Receiver's ExternalSecret (kubernetes/apps/flux/image-automation/
# receiver-janet-manifests.externalsecret.yaml).
#
# The SAME value must be set as the FLUX_WEBHOOK_TOKEN GitHub Actions secret on
# freckleapps/janet-brain (no github provider is wired into this tofu, so that
# step is manual — read the value from GSM/`tofu output`). FLUX_WEBHOOK_URL is
# the Receiver's runtime webhook path: https://atlantis-k8s01-flux-webhook.
# <tailnet>/hook/<.status.webhookPath>.
resource "random_bytes" "janet_flux_receiver" {
  length = 32
}

module "janet_flux_receiver_token" {
  source = "./modules/gsm-secret"

  cluster             = "atlantis-k8s01"
  namespace           = "flux-system"
  name                = "flux-receiver-janet"
  secret_data         = random_bytes.janet_flux_receiver.hex
  workload_project_id = local.project_id
  extra_labels = {
    consumer = "janet-brain"
  }
}
