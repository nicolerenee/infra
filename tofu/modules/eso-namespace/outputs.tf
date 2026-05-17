output "sa_subject" {
  description = "Full federated principal subject for this ESO identity (`system:serviceaccount:<ns>:<sa>`)."
  value       = "system:serviceaccount:${var.namespace}:${var.sa_name}"
}

output "secret_name_prefix" {
  description = "GSM secret name prefix this identity has access to (`<cluster>-<namespace>-`)."
  value       = "${var.cluster}-${var.namespace}-"
}

output "cluster" {
  description = "Cluster name (passthrough, useful for downstream modules)."
  value       = var.cluster
}

output "namespace" {
  description = "Namespace (passthrough, useful for downstream modules)."
  value       = var.namespace
}
