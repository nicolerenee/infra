# Bootstrapping a cluster

1. Deploy 1Password credentials: `./setup-1password.sh`
   - Select the vault containing Connect server credentials
   - Select the credentials document (DOCUMENT type)
   - Select the access token (API_CREDENTIAL type)
2. Run `helmfile sync`
   - prometheus-operator-crds
   - external-secrets
   - cilium
   - flux-operator
   - flux-instance

**Note:** Use `helmfile sync` instead of `helmfile apply` - apply runs a diff
first which fails on new clusters where CRDs don't exist yet.

If successful, Flux is now syncing with the repo and will reconcile the cluster
state.
