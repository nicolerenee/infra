---
description: Design for kube-apiservers on both clusters accepting freckle.id (Pocket ID) tokens, for people through kubectl and for the agent persona MCP servers through federated client credentials
---

# Kubernetes API: freckle.id sign-in

!!! note "Status: proposal"
    Nothing here is applied yet. This page is the design for review; the
    rollout at the end starts once it's approved.

Both clusters' API servers learn to accept JWTs issued by freckle.id
(Pocket ID). That gives two things:

- **People** can run `kubectl` as their freckle.id user, with RBAC from their
  freckle.id groups.
- **Agent persona MCP servers** (the cluster *observe* and *operate* personas)
  authenticate to the clusters as their own freckle.id identity, such as
  `freckle-id:agent:cluster-observe`. Each server swaps its ServiceAccount
  token for a freckle.id token, so it needs no stored secret, and each
  persona has its own least-privilege RBAC.

This is **additive**. The Tailscale API-server proxies stay exactly as they
are and remain the main way in. Agents never get `kubectl` or a kubeconfig;
they reach the clusters only through the persona MCP servers behind the
[MCP gateway](mcp-gateway.md).

## What exists today

| | fairy-k8s01 | atlantis-k8s01 |
| --- | --- | --- |
| Kubernetes / Talos | v1.37.2 / v1.14.5 | v1.37.2 / v1.14.5 |
| ServiceAccount issuer | `https://k8s-oidc.freckle.systems/fairy-k8s01` | `https://k8s-oidc.freckle.systems/atlantis-k8s01` |
| Tailscale API-server proxy | ProxyGroup `fairy-k8s01-kube-apiserver`, `mode: auth` | ProxyGroup `atlantis-k8s01-kube-apiserver`, `mode: auth` |
| Human/agent RBAC on the proxy | `system:masters` via the tailnet grant; `tag:infra-agent` → ClusterRole `infra-agent`; `tailscale-readers` → `view` | same |

freckle.id runs Pocket ID **v2.19.1** on atlantis (`freckle-id` namespace),
served at `https://freckle.id` on the `public` gateway with a cert-manager
certificate. OIDC clients are managed in OpenTofu with the `trozz/pocketid`
provider (2.5.0).

## Pocket ID: what "supports APIs" gives us

What we can rely on at v2.19.1, from what already runs here:

- **API resources.** An API resource is a named audience with permissions
  (scopes). Access tokens requested for it carry the resource identifier as
  `aud`. The MCP gateway's human route already depends on this:
  `https://mcp.fairy.freckle.services/mcp` with the permission `mcp:tools`.
  API resources are managed through the admin API or UI only; the tofu
  provider has no resource for them.
- **Federated identities on a client.** A client can list external
  identities that may authenticate *as* that client, each with `issuer`,
  `subject`, `audience` and an optional inline `jwks`
  (`pocketid_client.federated_identities` in the provider). The caller
  presents its own JWT as an RFC 7523 client assertion instead of a client
  secret. Any issuer with reachable JWKS works: our two ServiceAccount issuers
  (public on R2), Google, GitHub Actions
  (`https://token.actions.githubusercontent.com`).
- **Custom client IDs.** `client_id` is settable, so a persona's client can be
  called `cluster-observe` rather than a UUID.
- **Group claim.** ID tokens carry `groups` (Pocket ID group *names*) when the
  `groups` scope is requested. Cockpit's admin check reads it today.
- **Public clients with PKCE**, which is what a CLI login needs.

The design does not depend on any of the following. Rollout step 0 confirms
each one by decoding a real token:

- the exact claims of a client-credentials token (is `sub` the client ID? is
  there a `client_id` claim?);
- whether the `resource` parameter (RFC 8707) sets `aud` on a
  client-credentials grant, or whether `aud` is always the client ID;
- the access-token lifetime (expected to be 1 h).

The claim mapping below works either way; step 0 only fixes the literal
audience strings. **No Pocket ID upgrade is needed** unless step 0 turns up a
gap.

## API server configuration

Use Kubernetes **structured authentication configuration**
(`AuthenticationConfiguration`, `--authentication-config`), which is GA and
on by default at 1.37. Don't use the legacy `--oidc-*` flags. Structured
configuration gives us:

- CEL claim mappings and validation rules;
- several audiences per issuer (`audienceMatchPolicy: MatchAny`);
- live reload when the file changes, with no API server restart;
- an API server that still starts, and keeps serving every other
  authenticator, while the issuer is unreachable.

An issuer URL may appear in only one `jwt` entry, so a single freckle.id
authenticator serves both people and agents. CEL tells the two apart: a person
token carries `preferred_username`, and a client-credentials token doesn't.

```yaml
# /var/etc/kubernetes/authn/authentication-config.yaml (fairy; atlantis swaps the names)
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://freckle.id
      audienceMatchPolicy: MatchAny
      audiences:
        - kubernetes-fairy                      # people: kubelogin's ID token (aud = client ID)
        - https://api.fairy-k8s01.freckle.services  # agents: API resource audience (step 0 may swap this for the persona client IDs)
    claimValidationRules:
      # A person token must come from this cluster's own kubectl client, so a
      # token minted for another app (or for the other cluster) is rejected.
      - expression: >-
          !('preferred_username' in claims) ||
          (type(claims.aud) == string ? claims.aud == 'kubernetes-fairy' : 'kubernetes-fairy' in claims.aud)
        message: person tokens must be issued to the kubernetes-fairy client
      # Keeps the two namespaces apart even if a username could contain "agent:".
      - expression: "!('preferred_username' in claims) || !claims.preferred_username.startsWith('agent:')"
        message: reserved username prefix
    claimMappings:
      username:
        expression: >-
          'preferred_username' in claims
            ? 'freckle-id:' + claims.preferred_username
            : 'freckle-id:agent:' + claims.sub
      groups:
        expression: >-
          'preferred_username' in claims
            ? ('groups' in claims ? claims.groups.map(g, 'freckle-id:' + g) : [])
            : ['freckle-id:agents']
      uid:
        expression: claims.sub
```

- **Audience per cluster.** A fairy token is never accepted by atlantis: each
  cluster lists only its own `kubernetes-<cluster>` client and its own API
  resource. A persona that needs both clusters asks for two tokens.
- **Prefixes.** Every freckle.id identity starts with `freckle-id:`, so it
  can't collide with `system:` names, ServiceAccounts or the proxy's `tag:`
  groups.
- **Agent names.** `freckle-id:agent:<client_id>` (assuming `sub` is the
  client ID; if step 0 shows otherwise, the mapping reads `claims.client_id`).
  All agents also get the group `freckle-id:agents`, which the admission
  fence below matches on.

### Delivering the file with Talos

The audit policy already comes through a first-class Talos document
(`KubeAuditPolicyConfig`). Step 0 checks whether Talos 1.14 has the same for
authentication. If it does, use it. Otherwise:

- a new patch `talos/control-plane/03-authentication.yaml` per cluster writes
  the file under `/var/etc/kubernetes/authn/`;
- `KubeAPIServerConfig` mounts that directory read-only into the API server
  and sets `extraArgs.authentication-config` to the file.

The first apply restarts each API server once, because the flag is new. Later
edits, such as a new persona audience, only change the file, and the API
server reloads it live.

### Issuer reachability and TLS

- The issuer is the public `https://freckle.id`, the same URL every other
  client already uses. The certificate is publicly trusted, so the
  configuration sets no `certificateAuthority`.
- fairy fetches it over the internet. atlantis reaches its own public gateway
  the same way its pods already do: `homepage` on atlantis already does OIDC
  against `https://freckle.id`. Step 0 confirms the API server itself can
  fetch the discovery document. It runs on the host network, so the check is
  the API server's own log or its `apiserver_authentication_jwt_authenticator_*`
  metrics, not a pod.
- **Failure mode:** if freckle.id is down, new freckle.id logins and token
  exchanges fail. Tokens already issued keep validating against the cached
  JWKS until they expire. Nothing else is affected: the Tailscale proxy, the
  ServiceAccounts and the Talos admin kubeconfig use other authenticators.
- **Break-glass:** atlantis's self-dependency is known and accepted. The
  Talos admin contexts, plus the Talos configs that can mint a new admin
  kubeconfig (`talosctl kubeconfig`), don't depend on freckle.id.

## Tailscale API-server proxy: unchanged, plus a pass-through endpoint

An `auth`-mode proxy authenticates the caller by tailnet identity and
**impersonates** it. The caller's own bearer token never reaches the API
server, so a freckle.id token can't travel through the existing endpoint.
Switching those proxies to `noauth` would change how Nicole's current access
works, so they stay as they are.

**Recommendation: a second ProxyGroup per cluster in `noauth` mode**, next to
the existing one:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
metadata:
  name: fairy-k8s01-kube-apiserver-oidc
spec:
  type: kube-apiserver
  replicas: 2
  tags:
    - tag:fairy-k8s01-apiserver-oidc
  kubeAPIServer:
    mode: noauth
    hostname: fairy-k8s01-apiserver-oidc
```

- `fairy-k8s01-apiserver.<tailnet>` (auth mode) is unchanged. It's Nicole's
  main way in and keeps the tailnet-identity RBAC exactly as it is.
- `fairy-k8s01-apiserver-oidc.<tailnet>` (noauth) is Tailscale as transport
  only. The proxy terminates TLS with its tailnet certificate and passes the
  bearer token through, and the API server validates the freckle.id token.
  The tailnet ACL still decides who can reach it. This follows the "stay on
  Tailscale for transport" decision (C-238).
- Does Nicole's proxy access move to freckle.id? Not as part of this work.
  The freckle.id contexts sit next to the existing ones. Whether to use them
  day to day is her call later, and the auth-mode endpoint is never retired
  as part of it.
- **Tailnet policy change (Nicole):** a `tagOwners` entry for
  `tag:<cluster>-apiserver-oidc` on both clusters, and a grant letting her
  devices reach them. This goes with the Tailscale grants work (C-197).

The persona MCP servers don't use either proxy (next section).

### What happens to the `tag:infra-agent` RBAC

The ClusterRole `infra-agent`, bound to `tag:infra-agent` and `infra-agents`
through the auth-mode proxy, stays until agents move to the persona MCP
servers (C-192). It is then removed together with the VM's cluster access.
It is **not** converted to a freckle.id identity: the agents themselves get no
cluster identity, only the persona servers do.

## Agents: persona MCP servers as freckle.id identities

Agents call tools on the MCP gateway with their own ServiceAccount token, and
the gateway and cockpit gate and log every call. The cluster **observe** and
**operate** persona servers are what touch the API server. They authenticate
as follows:

1. **One server per cluster per persona**, running in that cluster, the same
   as the Flux and Victoria MCP backends (`flux-fairy`, `flux-atlantis`). Each
   talks to its own cluster's `kubernetes.default.svc`, so no API traffic
   crosses sites or the tailnet.
2. **The token it already has:** a projected ServiceAccount token with audience
   `https://freckle.id` and a 1 h expiry, rotated by the kubelet, from the
   cluster's public issuer.
3. **The exchange:**

    ```http
    POST https://freckle.id/api/oidc/token
    grant_type=client_credentials
    client_id=cluster-observe
    client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
    client_assertion=<projected ServiceAccount token>
    resource=https://api.fairy-k8s01.freckle.services
    ```

    Pocket ID matches the assertion against the client's federated identities:

    | issuer | subject | audience |
    | --- | --- | --- |
    | `https://k8s-oidc.freckle.systems/fairy-k8s01` | `system:serviceaccount:<ns>:cluster-observe` | `https://freckle.id` |
    | `https://k8s-oidc.freckle.systems/atlantis-k8s01` | `system:serviceaccount:<ns>:cluster-observe` | `https://freckle.id` |

4. **The result** is an access token with `aud` set to the cluster's API
   resource, valid for Pocket ID's access-token lifetime (expected 1 h). The
   server caches it, renews at 80 % of its life, and sends it as the bearer
   token from a client-go token source. Nothing is stored or mounted except
   the projected token.
5. **The API server** sees `freckle-id:agent:cluster-observe` in group
   `freckle-id:agents`, and that is the identity in the audit log. The cockpit
   gate records which run and item each call served.

Why a freckle.id identity rather than the server's own ServiceAccount? The
ServiceAccount alone would work in-cluster. freckle.id gives the persona the
same name on both clusters and on any other API that trusts freckle.id: the
GitHub broker (C-226), the cockpit, and Pocket ID itself. Every persona is
also a client we can disable in one place.

The same client pattern covers other federated callers with no new
machinery: GitHub Actions OIDC, a Google identity, or the container runner's
per-lane ServiceAccount. None of them gets Kubernetes RBAC in this design.

## RBAC in git

Shared app dir `kubernetes/apps/security/freckle-id-rbac/`, with a pointer
from each cluster:

| Subject | Binding | Notes |
| --- | --- | --- |
| `freckle-id:k8s-admins` (Group) | `cluster-admin` | People. See the decision below on who's in it. |
| `freckle-id:k8s-viewers` (Group) | `view` | Optional read-only for people. |
| `freckle-id:agent:cluster-observe` (User) | ClusterRole `freckle-agent-observe` | `get/list/watch` on every API group (`*`); the core group listed resource by resource **without `secrets`**; `pods/log`; no `exec`, no `portforward`, no `proxy`. |
| `freckle-id:agent:cluster-operate` (User) | ClusterRole `freckle-agent-operate` | Observe, plus `patch` on Flux Kustomizations and HelmReleases (reconcile, suspend and resume), `patch` on Deployments, StatefulSets and DaemonSets (rollout restart), and `create` on Jobs (rerun a CronJob). The exact tool list belongs to C-192. |

Rules for every agent identity:

- no `cluster-admin`;
- no `secrets`, `pods/exec`, `serviceaccounts/token`, `impersonate`, `bind`
  or `escalate`;
- no writes to `rbac.authorization.k8s.io` or `admissionregistration.k8s.io`.

As a second fence, a `ValidatingAdmissionPolicy` matching group
`freckle-id:agents` denies RBAC, CRD, admission-policy and ProxyGroup writes,
like the existing `infra-agent-no-privilege-changes`.

## Nicole's kubeconfig

There is one public Pocket ID client per cluster: `kubernetes-fairy` and
`kubernetes-atlantis`. Each uses PKCE with no secret, has callbacks
`http://localhost:8000` and `http://localhost:18000` (kubelogin's defaults),
and has `allowed_user_groups` set to the admin and viewer groups. The
contexts are added next to the existing ones:

```yaml
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
      cluster: fairy-k8s01-apiserver-oidc   # https://fairy-k8s01-apiserver-oidc.<tailnet>
      user: freckle-id-fairy
```

## Decisions for Nicole

1. **Which freckle.id account is cluster-admin.** The house rule is that the
   everyday account never gets admin. Proposal: a new group `k8s-admins`
   holding only the separate admin account, and the everyday account in
   `k8s-viewers`. The existing `sysadmins` group isn't reused, because it
   also gates other admin UIs.
2. **The second (noauth) ProxyGroup** with its tailnet tag and grant, rather
   than reaching `api.<cluster>.freckle.services` directly.
3. **API resource per cluster** (`https://api.<cluster>.freckle.services`) as
   the agent audience. These are created by hand through the admin UI, since
   tofu can't manage them. The alternative is listing each persona's client
   ID as an audience.

## Rollout (after approval)

0. **Probe.** Create the `cluster-observe` client and the fairy API resource.
   Mint one token from a throwaway pod using the persona ServiceAccount and
   decode it (claims only, never the token itself). Fix the literal
   audience and `sub` mapping. Also check what Talos 1.14 offers for the
   authentication file.
1. **Pocket ID** (freckleapps/tofu, Nicole reviews):
   - groups `k8s-admins` and `k8s-viewers`; membership is set in the UI;
   - clients `kubernetes-fairy` and `kubernetes-atlantis`;
   - persona clients `cluster-observe` and `cluster-operate` with their
     federated identities.

   Manual steps for Nicole in the admin UI: the two API resources, each with
   access granted to the persona clients.
2. **Second ProxyGroup** per cluster (public repo), plus the tailnet tag and
   grant (Nicole).
3. **RBAC** shared app dir and pointers (public repo). This is inert until
   the API servers trust the issuer.
4. **Talos patch** in git. Nicole applies it to one control-plane node at a
   time with topf, fairy first, and checks `kubectl get --raw /readyz` and the
   API server log after each node. Then atlantis.
5. **Nicole's contexts.** `kubectl --context fairy-freckle-id auth whoami`
   shows `freckle-id:<user>` and her `freckle-id:` groups.
6. **Pilot:** the cluster observe persona server (C-192), read-only. It logs a
   `SelfSubjectReview` at startup showing `freckle-id:agent:cluster-observe`.
   A `SelfSubjectAccessReview` for `get secrets` and `patch deployments`
   comes back denied.
