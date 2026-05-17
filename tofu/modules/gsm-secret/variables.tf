variable "cluster" {
  description = "Full cluster name (e.g., fairy-k8s01). Forms part of the secret_id prefix."
  type        = string
}

variable "namespace" {
  description = "K8s namespace that owns this secret. Forms part of the secret_id prefix."
  type        = string
}

variable "name" {
  description = "Consumer-specific suffix. Final secret_id is `<cluster>-<namespace>-<name>`."
  type        = string
}

variable "secret_data" {
  description = "Secret value (string). Use jsonencode({...}) for structured secrets so ESO's dataFrom.extract can parse keys."
  type        = string
  sensitive   = true
}

variable "workload_project_id" {
  description = "GCP project ID hosting the GSM secret."
  type        = string
}

variable "extra_labels" {
  description = "Additional labels to merge with the defaults (cluster, namespace). Use for consumer/purpose tags."
  type        = map(string)
  default     = {}
}
