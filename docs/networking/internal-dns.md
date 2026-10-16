---
description: Internal-only DNS for both sites — a hidden BIND9 primary fed by external-dns and tofu, per-site authoritative secondaries, and site gateways that forward only the internal domains to them
---

# Internal DNS

`freckle.services`, `freckle.systems`, `freckle.media`, `freckle.network` and
the two site reverse zones are served whole by BIND9 inside the clusters.
Internal-only names in them only resolve from inside the network; public DNS
at Cloudflare never learns them.

The three `freckle.*` zones are split-horizon: Cloudflare keeps serving the
public view, BIND serves a superset internally, and the gateways forward the
whole zones to BIND. Anything published publicly by something other than
our two clusters' external-dns (tofu-managed records, mail records, another
cluster, hand edits) has to be mirrored in tofu or it vanishes from the
inside view — `internal-dns-records.tf` in the private repo is that list.

## Zones

| Zone | Purpose | Written by |
|------|---------|------------|
| `freckle.services` / `freckle.systems` / `freckle.media` | whole zones, superset of public: every record either cluster publishes plus the mirrored non-cluster ones | external-dns (both), tofu |
| `freckle.network` | network gear, OOB, anything not a Kubernetes Service; `<host>.den1` and `<host>.btx1` | tofu |
| `140.10.in-addr.arpa` | den1 reverse (10.140.0.0/16) | tofu |
| `189.10.in-addr.arpa` | btx1 reverse (10.189.0.0/16) | tofu |

Every zone is **dynamic**: the skeleton (SOA + NS) is written once by the
primary's init container and every record after that arrives as an RFC2136
update. Never edit a zone file on the PVC by hand.

## Components

```text
external-dns (fairy) ──RFC2136──┐
external-dns (atlantis) ─RFC2136┤
tofu (hashicorp/dns) ───RFC2136─┤
                                ▼
                 bind9-primary  (atlantis, hidden, 10.140.250.54)
                     │ AXFR + NOTIFY (TSIG freckle-dns-xfr)
         ┌───────────┴───────────┐
         ▼                       ▼
bind9-secondary (fairy)   bind9-secondary (atlantis)
   10.189.250.53             10.140.250.53
         ▲                       ▲
   UDM forward-domain      den1 gateway forward-domain
   (internal zones only)   (internal zones only)
```

- **bind9-primary** — `kubernetes/apps/networking/bind9/primary`, one replica on
  atlantis with a `ceph-block` PVC for the zone journals. Never handed to
  clients; it takes updates with the `freckle-dns-update` TSIG key and NOTIFYs
  both secondaries. Losing it freezes updates, never resolution.
- **bind9-secondary** — `kubernetes/apps/networking/bind9/secondary`, two
  replicas per cluster behind a pinned internal LoadBalancer IP. Authoritative
  for the hosted zones, plus just enough recursion (forward-only, DNS-over-TLS
  to Cloudflare, internal clients only) to complete CNAME chains that leave
  our zones — the UDM does not chase those, and stub resolvers cannot; zones on emptyDir because a PVC would make DNS depend
  on Ceph during a cold start, and a fresh pod simply re-pulls from the
  primary. SOA expiry is 14 days so a secondary keeps serving long after the
  primary goes away.
- **external-dns-internal** — `kubernetes/apps/networking/external-dns/internal`,
  one per cluster, `rfc2136` provider, the three `freckle.*` zones. No gateway label filter: it mirrors every route on every
  gateway (tailnet, tunnel, internal), so the internal zone is a superset of
  the public one. Separate `txtOwnerId` (`<cluster>-internal`) from the
  Cloudflare instances.
- **Static records** — `tofu/platform/internal-dns-records.tf` in the private
  repo: one host map that generates the `freckle.network` A/AAAA records and
  the matching PTRs, internal twins of every tofu-managed Cloudflare record
  (cluster API names, tunnel gateways), and the hand-kept mirrors (mail
  records, the R2-backed `k8s-oidc`/`k8s-schemas` names, another cluster's
  names).

Both TSIG keys and the ESO grants for the `dns` namespace come from
`tofu/platform/internal-dns.tf` (private repo) via GSM.

## Who resolves what

Site gateways are the only resolvers clients see. Each forwards just the
six hosted zones to its site's secondary and resolves everything else
itself, so the gateway's own DNS features (filtering, logging, encrypted
upstream) stay in the loop. BIND's only upstream traffic is DoT to Cloudflare
for CNAME targets outside our zones.

| Client | Resolver | Internal zones go to |
|--------|----------|----------------------|
| fairy LAN + Talos nodes | UDM (DHCP; nodes use the compute-VLAN gateway 10.189.3.1) | UniFi **Forward Domain** DNS policies → 10.189.250.53 (`network/btx01/udm-dns` in the private repo, Integration API) |
| atlantis Talos nodes | the secondaries directly: 10.140.250.53 then 10.189.250.53 | authoritative locally; the rest forwarded over DoT |
| den1 devices | nothing yet — border1 runs no resolver; the UniFi gateway on order will get the same Forward Domain policies as fairy | — |
| Tailnet | MagicDNS split DNS for the internal domains | both secondaries |
| Pods | kube-dns → node resolvers | same path as the node |

Guest and IoT VLANs can resolve the names; the firewall is what denies them
access.

## Failure modes

- **Whole cluster reboots.** Nodes resolve via the gateway, whose default
  upstream is unaffected, so kubelet and image pulls never wait on anything
  internal. That cluster's own internal names are unavailable until its
  secondary is back (seconds after the CNI), which is roughly when the
  services behind them return anyway.
- **Primary down.** Secondaries serve their copies for up to 14 days;
  external-dns and tofu updates queue until it returns.
- **Tunnel down.** Each site's secondary keeps answering from its last
  transfer. The fairy secondary cannot refresh until the tunnel returns.

## Operating

```bash
# Is a zone loaded and current on a secondary?
dig +short SOA fairy.freckle.services @10.189.250.53
dig +short SOA fairy.freckle.services @10.140.250.53   # serials should match

# What did external-dns write? (TSIG-authenticated AXFR from the primary)
kubectl -n dns exec deploy/bind9-primary -- \
  dig +short AXFR fairy.freckle.services @127.0.0.1 -p 5353 -k /secrets/tsig-keys.conf

# Primary / secondary logs show every update, transfer and NOTIFY
kubectl -n dns logs deploy/bind9-primary
```

Adding a static host: edit `internal_hosts` in `internal-dns-records.tf`,
`tofu apply` from a machine on the tailnet (the provider talks RFC2136 to
the primary at 10.140.250.54).
