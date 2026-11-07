---
description: Design for kube-apiservers on both clusters accepting freckle.id (Pocket ID) sign-in for people through kubectl, with RBAC from freckle.id groups
---

# Kubernetes API: freckle.id sign-in

!!! note "Status: proposal"
    Nothing here is applied yet. This page is the design for review; the
    rollout at the end starts once it's approved.

Both clusters' API servers learn to accept ID tokens issued by freckle.id
(Pocket ID), so people can run `kubectl` as their freckle.id user. RBAC binds
to freckle.id **groups**, so a membership change in Pocket ID takes effect on
the next token, with no change in git.

This is **additive**. The Tailscale API-server proxies stay exactly as they
are, and so do the Talos admin kubeconfigs.

!!! info "People only, by design"
    freckle.id sign-in on the API servers is for people. Agents never touch
    the Kubernetes API: they use MCP tools. The MCP servers that do call the
    API (the cluster *operate* server, C-436, and the *observe* reads) use
    plain in-cluster ServiceAccounts in the cluster they serve, with
    ClusterRoles/Roles as their personas. So there are no persona clients,
    federated identities or API resources in Pocket ID for Kubernetes.

## What exists today

| | fairy-k8s01 | atlantis-k8s01 |
| --- | --- | --- |
| Kubernetes / Talos | v1.37.2 / v1.14.5 | v1.37.2 / v1.14.5 |
| API endpoint | `https://api.fairy-k8s01.freckle.services:6443` | `https://api.atlantis-k8s01.freckle.services:6443` |
| Tailscale API-server proxy | ProxyGroup `fairy-k8s01-kube-apiserver`, `mode: auth` | ProxyGroup `atlantis-k8s01-kube-apiserver`, `mode: auth` |
| API server config | `KubeAPIServerConfig` document (`talos/control-plane/01-cluster.yaml`) | same |

freckle.id runs Pocket ID **v2.19.1** on atlantis (`freckle-id` namespace),
served at `https://freckle.id` on the `public` gateway with a publicly
trusted certificate. OIDC clients and groups are managed in OpenTofu
(frecklelabs/tofu `platform/`) with the `trozz/pocketid` provider 2.5.0;
group membership is set in the Pocket ID admin UI.

What sign-in needs from Pocket ID is all standard OIDC, already used by other
apps here:

- **Public clients with PKCE**, so `kubectl oidc-login` needs no client
  secret.
- **ID token `aud` is the client ID.** kubelogin hands the API server the ID
  token, so the audience check is just the cluster's client ID.
- **`groups` claim** with Pocket ID group names, when the `groups` scope is
  requested (paperless, nautobot and the cockpit read it today).
- **`allowed_user_groups`** on the client, so only `k8s-admins` members can
  get a token at all.

No Pocket ID upgrade is needed.

## Pocket ID clients and group

| Object | Settings |
| --- | --- |
| Group `k8s-admins` | Members: `nicole` and `alt-nicole`. Kubernetes is only ever used as an admin, so the everyday account is in it on purpose. |
| Client `kubernetes-fairy` | Custom `client_id`, `is_public = true`, `pkce_enabled = true`, callbacks `http://localhost:8000` and `http://localhost:18000` (kubelogin's defaults), `allowed_user_groups = [k8s-admins]`. |
| Client `kubernetes-atlantis` | Same, for atlantis. |

One client per cluster means a token's `aud` names exactly one cluster, so a
fairy token is never accepted by atlantis. A `k8s-viewers` group isn't
created; it can be added later if something needs read-only people access.

## API server configuration

Use Kubernetes **structured authentication configuration**, not the legacy
`--oidc-*` flags. Talos 1.14 has a first-class document for it,
`KubeAuthenticationConfig`. Both clusters already use the `KubeAPIServerConfig`
document, so Talos already runs the API server with `--authentication-config`
(today holding only the anonymous health-check rules). Adding the JWT
authenticator is a change to that document, which Talos applies live.

```yaml
# kubernetes/clusters/fairy-k8s01/talos/control-plane/03-authentication.yaml
# (atlantis: the same file with kubernetes-atlantis)
---
apiVersion: v1alpha1
kind: KubeAuthenticationConfig
configuration:
  # Talos's default: unauthenticated health checks only. Restated so the
  # patch can't drop it.
  anonymous:
    enabled: true
    conditions:
      - path: /livez
      - path: /readyz
      - path: /healthz
  jwt:
    - issuer:
        url: https://freckle.id
        audiences:
          - kubernetes-fairy
      claimValidationRules:
        - expression: "has(claims.preferred_username) && claims.preferred_username != ''"
          message: freckle.id token has no preferred_username
      claimMappings:
        username:
          expression: "'freckle-id:' + claims.preferred_username"
        groups:
          expression: "has(claims.groups) ? claims.groups.map(g, 'freckle-id:' + g) : []"
        uid:
          expression: claims.sub
```

- **Names.** A person is `freckle-id:<preferred_username>` and their groups
  are `freckle-id:<group>`. The prefix keeps them apart from `system:` names,
  ServiceAccounts and the Tailscale proxy's identities. `uid` is the stable
  Pocket ID user ID, for the audit log.
- **Audience.** Only this cluster's client is listed. With a single audience,
  `audienceMatchPolicy` is not needed.
- **Prefixes and expressions.** CEL expression mappings carry no `prefix`
  field; the prefix is part of the expression.
- **Rendering.** Talos writes the file itself (with the
  `apiserver.config.k8s.io/v1beta1` type header, which 1.37 still serves;
  CEL mappings are in v1beta1). Before applying, diff the rendered config
  (`topf` diff or `talosctl apply-config --dry-run`) and check that the
  `anonymous` block and the `jwt` entry both survive the merge.

### Issuer reachability, TLS and break-glass

- The issuer is the public `https://freckle.id`, the URL every other client
  uses. Its certificate is publicly trusted, so the config sets no
  `certificateAuthority`. fairy fetches discovery and JWKS over the internet;
  atlantis reaches its own public gateway the way its pods already do.
- An unreachable issuer doesn't stop the API server: it starts and serves
  every other authenticator, and only freckle.id logins fail. Tokens already
  issued keep validating against the cached JWKS until they expire. Check
  after the first node with the API server log and the
  `apiserver_authentication_jwt_authenticator_*` metrics.
- **Break-glass:** atlantis depending on a workload it runs is known and
  accepted. The Talos `admin@<cluster>` kubeconfigs, and the Talos configs
  that can mint a new one (`talosctl kubeconfig`), don't depend on freckle.id.

## How people reach the API server

Clients reach `https://api.<cluster>.freckle.services:6443` **directly** by
default. That name is the cluster endpoint, so it is already in the API
server certificate, and the kubeconfig trusts the cluster CA (the same
`certificate-authority-data` as the Talos admin kubeconfig). The network
path to it is Nicole's to arrange; this design adds no Tailscale ProxyGroup,
tag or grant.

The Tailscale API-server proxies (`<cluster>-apiserver.<tailnet>`, `auth`
mode) are unchanged. An `auth`-mode proxy impersonates the tailnet identity
and doesn't forward the caller's bearer token, so freckle.id contexts don't
go through it.

## RBAC in git

A shared app dir `kubernetes/apps/auth/kubernetes-rbac/`, with a Flux
Kustomization pointing at it from each cluster's `kube-system` apps:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: freckle-id-k8s-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: freckle-id:k8s-admins
```

Bindings name groups only, never `freckle-id:<user>`, so who has access is
decided by group membership in Pocket ID. The binding is inert until the API
servers trust the issuer, so it can merge first.

## Nicole's kubeconfig

New contexts sit next to the existing ones:

```yaml
clusters:
  - name: fairy-k8s01-direct
    cluster:
      server: https://api.fairy-k8s01.freckle.services:6443
      certificate-authority-data: <cluster CA, from the Talos admin kubeconfig>
users:
  - name: freckle-id-fairy
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1
        command: kubectl
        args:
          - oidc-login
          - get-token
          - --oidc-issuer-url=https://freckle.id
          - --oidc-client-id=kubernetes-fairy
          - --oidc-extra-scope=profile
          - --oidc-extra-scope=groups
contexts:
  - name: fairy-freckle-id
    context:
      cluster: fairy-k8s01-direct
      user: freckle-id-fairy
```

## Rollout (after approval)

1. **Pocket ID** (frecklelabs/tofu PR, Nicole reviews): group `k8s-admins`,
   clients `kubernetes-fairy` and `kubernetes-atlantis`. After apply, Nicole
   adds `nicole` and `alt-nicole` to the group in the admin UI.
2. **Probe the kubectl login on fairy** before the API server trusts
   anything: `kubectl oidc-login setup --oidc-issuer-url=https://freckle.id
   --oidc-client-id=kubernetes-fairy --oidc-extra-scope=profile
   --oidc-extra-scope=groups`, and check the decoded claims (never the token
   itself): `iss`, `aud = kubernetes-fairy`, `preferred_username`, and
   `groups` containing `k8s-admins`. Adjust the mapping if a claim differs.
3. **RBAC** (public repo, merges on green): the shared dir and both
   pointers.
4. **Talos patch for fairy** (public repo): `03-authentication.yaml`. Nicole
   applies it one control-plane node at a time with topf, checking
   `kubectl get --raw /readyz` with the admin context and the API server log
   after each node. Then `kubectl --context fairy-freckle-id auth whoami`
   shows `freckle-id:<user>` with `freckle-id:k8s-admins`.
5. **atlantis**: the same patch with `kubernetes-atlantis`, applied the same
   way, then the same `auth whoami` check. A fairy token sent to atlantis's
   API server gets a 401.
