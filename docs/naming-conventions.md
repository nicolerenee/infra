---
description: Device and cluster naming conventions used across all sites
---

# Naming Conventions

All infrastructure devices follow a consistent naming scheme that encodes
location, role, and instance number. The goal is to identify any device's
purpose and physical location from its hostname alone.

## General Format

```
{location}-{role}{##}
```

- **location** — where the device physically lives (rack ID or site prefix)
- **role** — abbreviated function (see table below)
- **##** — two-digit instance number, zero-padded (01, 02, etc.)

Site-level devices that aren't tied to a specific rack drop the location
prefix (e.g., `gw01`, `store01`).

## Role Abbreviations

| Abbreviation | Meaning | Example |
|--------------|---------|---------|
| `cn` | Compute node | r02-cn01 |
| `dgx` | DGX Spark GPU node | r02-dgx01 |
| `gw` | Gateway / router | gw01 |
| `tor` | Top-of-rack switch | r02-tor01 |
| `asw` | Access switch | mdf-asw01 |
| `msw` | Management switch | r02-msw01 |
| `fsw` | Fabric switch | r02-fsw01 |
| `vsw` | PoE / video switch | mdf-vsw01 |
| `ups` | Uninterruptible power supply | r02-ups01 |
| `pdu` | Power distribution unit | r02-pdu01 |
| `store` | Storage appliance | store01 |
| `nvr` | Network video recorder | nvr01 |

## Location Prefixes

| Prefix | Meaning |
|--------|---------|
| `r02` | Fairy site compute rack (32U) |
| `mdf` | Fairy site MDF rack (9U) |
| `atlantis` | Atlantis site (Denver colocation) |

Devices without a prefix are site-level — they belong to the site but
aren't associated with a specific rack (e.g., `gw01`, `store01`).

## Cluster Names

Kubernetes clusters follow `{site}-k8s{##}`:

| Cluster | Site |
|---------|------|
| fairy-k8s01 | Fairy |
| atlantis-k8s01 | Atlantis |

## BMC / IPMI Names

Out-of-band management interfaces append `-bmc` and optionally a site
suffix:

```
{nodename}-bmc.{site}
```

Example: `compute01-bmc.den1` for the BMC of atlantis-compute01 at the
Denver facility.

## Examples

| Name | Reads as |
|------|----------|
| `r02-cn03` | Rack 02, compute node 3 |
| `r02-dgx01` | Rack 02, DGX Spark node 1 |
| `mdf-asw01` | MDF, access switch 1 |
| `r02-tor01` | Rack 02, top-of-rack switch 1 |
| `gw01` | Gateway 1 (site-level) |
| `store01` | Storage appliance 1 (site-level) |
| `fairy-k8s01` | Fairy site, Kubernetes cluster 1 |
