output "secret_id" {
  description = "The secret's full name (e.g., `fairy-k8s01-cloudflared-tunnel-token`). Reference this from ESO's remoteRef.key."
  value       = google_secret_manager_secret.this.secret_id
}

output "secret" {
  description = "The full secret resource — pass this to other resources that need a secret reference (IAM members, secret_iam_binding, etc.)."
  value       = google_secret_manager_secret.this
}

output "secret_version" {
  description = "The first secret_version resource. Useful for forcing dependencies on secret content existing before consuming."
  value       = google_secret_manager_secret_version.this
}
