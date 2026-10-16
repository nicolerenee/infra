---
description: Internal-only DNS for both sites — a hidden BIND9 primary fed by external-dns and tofu, per-site authoritative secondaries, and site gateways that forward only the internal domains to them
---

# Internal DNS

Internal names (`*.fairy.freckle.*`, `*.atlantis.freckle.*`, `freckle.network`
and the two site reverse zones) are served by BIND9 inside the clusters and
only resolve from inside the network. Public DNS at Cloudflare never learns
them.

## Zones

| Zone | Purpose | Written by |
|------|---------|------------|
| `fairy.freckle.systems` / `.services` / `.media` | fairy-k8s01 services | external-dns (fairy) |
| `atlantis.freckle.systems` / `.services` / `.media` | atlantis-k8s01 services | external-dns (atlantis) |
| `freckle.network` | network gear, OOB, anything not a Kubernetes Service; `<host>.den1` and `<host>.btx1` | tofu |
| `140.10.in-addr.arpa` | den1 reverse (10.140.0.0/16) | tofu |
| `189.10.in-addr.arpa` | btx1 reverse (10.189.0.0/16) | tofu |

Every zone is **dynamic**: the skeleton (SOA + NS) is written once by the
primary's init container and every record after that arrives as an RFC2136
update. Never edit a zone file on the PVC by hand.

## Components

```
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
  only (`recursion no`); zones on emptyDir because a PVC would make DNS depend
  on Ceph during a cold start, and a fresh pod simply re-pulls from the
  primary. SOA expiry is 14 days so a secondary keeps serving long after the
  primary goes away.
- **external-dns-internal** — `kubernetes/apps/networking/external-dns/internal`,
  one per cluster, `rfc2136` provider, limited to that cluster's three
  subzones. Picks up HTTPRoutes on gateways labelled
  `gateway.freckle.systems/dns: internal` and LoadBalancer Services with a
  hostname annotation. Separate `txtOwnerId` (`<cluster>-internal`) from the
  Cloudflare instance.
- **Static records** — `tofu/platform/internal-dns-records.tf` in the private
  repo, one host map that generates the `freckle.network` A/AAAA records and
  the matching PTRs.

Both TSIG keys and the ESO grants for the `dns` namespace come from
`tofu/platform/internal-dns.tf` (private repo) via GSM.

## Who resolves what

Site gateways are the only resolvers clients see. Each forwards just the
nine hosted zones to its site's secondary and resolves everything else
itself, so BIND never talks to the internet and the gateway's own DNS
features (filtering, logging, encrypted upstream) stay in the loop.

Forward the **exact zones**, never the bare TLDs: `freckle.services`,
`freckle.systems` and `freckle.media` also carry public apex records, and an
authoritative-only server answers REFUSED for any name outside its zones.

| Client | Resolver | Internal zones go to |
|--------|----------|----------------------|
| fairy LAN + Talos nodes | UDM (DHCP) | UniFi **Forward Domain** records → 10.189.250.53 (`network/btx01/udm-dns` in the private repo) |
| den1 LAN + Talos nodes | den1 gateway | per-zone forward → 10.140.250.53 (VyOS `service dns forwarding domain <zone> name-server …` until the UniFi gateway lands) |
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
