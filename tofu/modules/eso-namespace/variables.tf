variable "cluster" {
  description = "Full cluster name (e.g., fairy-k8s01). Used both as the secret-name prefix scope and in the IAM condition title/description."
  type        = string
}

variable "namespace" {
  description = "K8s namespace where ESO runs and where the SA lives."
  type        = string
}

variable "sa_name" {
  description = "K8s ServiceAccount name ESO authenticates as. The federated principal subject is `system:serviceaccount:<namespace>:<sa_name>`."
  type        = string
}

variable "workload_project_id" {
  description = "GCP project ID hosting the GSM secrets. The IAM grant applies at this project level."
  type        = string
}

variable "workload_project_number" {
  description = "Numeric ID of the workload project (data.google_project.this.number). Used in the IAM condition's resource.name pattern."
  type        = string
}

variable "iac_project_number" {
  description = "Numeric ID of the IaC admin project where the WIF pool lives. Used in the federated principal URI."
  type        = string
}

variable "wif_pool_id" {
  description = "WIF pool ID (the short name, not the full path). Used in the federated principal URI."
  type        = string
}
