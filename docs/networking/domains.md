---
description: The domain plan — which freckle.* zone a name belongs in, which label it carries (physical site vs environment code name), and how internal-only versus public is decided
---

# Domains

Every name answers three questions: **what is it** (picks the zone), **where
is it** (picks the label), and **who may reach it** (a gateway decision, never
part of the name). Decided 2026-10-16; supersedes the May 2026 mapping that
kept hosts on `freckle.systems`.

## Zones and roles

| Zone | Role | Label |
|------|------|-------|
| `freckle.network` | anything physical or infra: servers, BMCs, switches, routers, firewalls, APs, PDUs, UPSes, the NAS | **site** (`btx1`, `den1`) |
| `freckle.tools` | anything a human opens: app UIs, ops UIs (Grafana, Hubble, Rook, Alertmanager, Flux), storage as a service alias | **environment** (`fairy`, `atlantis`) |
| `freckle.services` | anything a machine talks to: Kubernetes API, OIDC issuer and JWKS, schema host, webhooks, MCP endpoints, S3, tunnel plumbing | environment |
| `freckle.media` | the media stack (Jellyfin, Plex, *arr, downloaders) | environment |
| `freckle.chat` | Matrix | — |
| `freckle.id` | identity provider | — |
| `freckle.family` | public-facing family things | — |
| `freckle.games` | game servers | environment |
| `freckle.rocks` | personal public sites | — |
| `freckle.systems` | **retired** — draining to empty; no new names | — |
| `freckle.vision`, `freckle.build`, `freckle.email`, `freckle.community`, `freckle.management` | parked; registered because available | — |
| `frecklefamily.com`, `frecklesystems.com` | redirects to the dot-TLD siblings only | — |

A function zone wins over `freckle.tools` when one fits: Sonarr is
`sonarr.fairy.freckle.media`, not `.tools`.

### `.tools` or `.services`?

Open the name in a browser. **A page** means `.tools`. **JSON, a 401, or a
protocol handshake** means `.services` — even if a person once pasted the URL
into a config. MCP endpoints, the Kubernetes API, webhooks and OIDC discovery
are all `.services`.

The split is about gateway treatment, not taste: `.tools` names get the login
redirect, the ID-token cookie and friendly error pages; `.services` names get
bearer tokens, mTLS or no auth, and a login redirect there is a bug. Keeping
them on separate zones lets gateway policy and certificate SANs follow the
domain instead of being per-route exceptions.

## Labels

Two label sets with two meanings. They look alike today because each site
hosts one environment, but they are different axes.

| Physical site (`.network`) | Environment code name (everything else) |
|---|---|
| `btx1` — the house | `fairy` — the house's environment (the house keeps its name across moves) |
| `den1` — the colo | `atlantis` — the colo's environment |

A datacenter is always named by site: moving it is a new site, not a lift. The
environment names stay put through a move, so every `.network` name changes
and nothing on `.tools` or `.services` does.

A service that spans environments, or is not tied to one, drops the label:
`harvest.freckle.tools`, `watch.freckle.media`.

## Patterns

| Kind | Pattern | Example |
|------|---------|---------|
| Host, primary interface | `<host>.<site>.freckle.network` | `store01.btx1.freckle.network` |
| Host, out-of-band / BMC | `<host>-mgmt.<site>.freckle.network` | `cn02-mgmt.btx1.freckle.network` |
| Host, extra interface | `<iface>.<host>.<site>.freckle.network` | `e1-48.spine1.den1.freckle.network` |
| Human-facing app | `<app>.<env>.freckle.tools` | `grafana.fairy.freckle.tools` |
| Storage as a service | `<role>.<env>.freckle.tools` → CNAME to the host | `fs.fairy.freckle.tools` → `store01.btx1.freckle.network` |
| Machine endpoint | `<name>.<env>.freckle.services` | `api.fairy.freckle.services` (Kubernetes API) |
| Environment-less machine endpoint | `<name>.freckle.services` | `k8s-oidc.freckle.services`, `fairy-cf-tun-gw.freckle.services` |
| Function zone app | `<app>.<env>.<zone>` | `sonarr.fairy.freckle.media` |

Hosts and services are different things: a NAS is a host on `.network`; the
share people mount is a service alias on `.tools`. Replace the NAS and only
the alias moves.

## Exposure

**Nothing on the internal gateway is anonymous.** The tailnet gateway got
identity for free from Tailscale ACLs; the internal gateway is reachable from
every allowed VLAN, so every route on it must be gated before it moves: either
the app's own login (Grafana, Paperless, Mealie…) or an Envoy Gateway
`SecurityPolicy` (OIDC against pocket-id, with the `jwt` provider validating
the cookie — see `kubernetes/apps/networking/cilium/app/oidc.yaml`). The
network layer adds a second cut: the UDM keeps guest and IoT VLANs away from
the internal LB pools entirely.

**Every name exists in the internal zones.** It exists publicly only when a
route sits on the tunnel or public gateway, because only the Cloudflare
external-dns instances write public records. Moving an app from internal-only
to public is a `parentRef` change; the hostname never moves.

- `freckle.network` never has public records. The Cloudflare zone stays
  delegated but empty so DNS-01 can still issue certificates for internal
  names (ACME only needs the `_acme-challenge` TXT to be public).
- `freckle.tools`, `freckle.services`, `freckle.media` (and `freckle.systems`
  until it is empty) are split-horizon: Cloudflare serves the public view,
  BIND serves a superset internally. See [Internal DNS](internal-dns.md).

### MCP servers

MCP endpoints are `.services` names, but they never get a route of their own:
all of them sit behind the [MCP gateway](mcp-gateway.md), which gives humans a
freckle.id login and agents a ServiceAccount-token check, plus per-caller tool
authorization. One name for humans (`mcp.<env>.freckle.services`), one for
agents (`mcp-agents.<env>.freckle.services`).

## Reverse DNS

PTRs come only from the `freckle.network` host map in the private repo
(`tofu/platform/internal-dns-records.tf`): one source for forward and reverse.
LoadBalancer addresses get no PTRs.

## Migration

1. `.tools` added to the internal DNS stack (done with this page) so new
   names resolve before anything moves.
2. Hosts: den1 and btx1 iron into the `freckle.network` map; `hw.freckle.systems`
   and the old `*.den1.freckle.systems` names retired; device-held aliases
   created (`fs.fairy.freckle.tools`) with a transition CNAME from the old
   name until clients are re-pointed.
3. Machine endpoints: the three API names → `api.<env>.freckle.services`;
   OIDC issuer, JWKS and schemas → `.services`. The OIDC issuer is trusted by
   the WIF pool, so the old name stays until the pool is re-bootstrapped.
4. Human-facing apps move during the internal gateway migration, one route
   at a time, with certificates following the routes.
5. `freckle.systems` goes quiet; its certificate SANs shrink to nothing; the
   zone is left delegated and empty.

### Transition aliases

| Old name | New name | Remove when |
|----------|----------|-------------|
| `store01.fairy.freckle.systems` | `fs.fairy.freckle.tools` | laptops' Time Machine targets re-pointed |
