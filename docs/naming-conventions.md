---
description: Device and cluster naming conventions used across all sites
---

# Naming Conventions

All infrastructure devices follow a consistent naming scheme that encodes
site, location, role, and instance number. The goal is to identify any
device's site, physical location, and purpose from its hostname alone.

## General Format

Rack-mounted devices:

```text
{site}-{rack}-{role}{##}
```

Site-level devices (not tied to a specific rack):

```text
{site}-{role}{##}
```

- **site** — short code identifying the physical site (see below)
- **rack** — rack or infrastructure location within the site
- **role** — abbreviated function (see table below)
- **##** — two-digit instance number, zero-padded (01, 02, etc.)

Every device name starts with the site code. This avoids ambiguity when
rack IDs like `r01` or `r02` exist at multiple sites.

## Sites

A **site** is a physical location with its own network, power, and
infrastructure.

| Code | Site | Location |
|------|------|----------|
| `fairy` | Fairy | Home office (primary) |
| `atlantis` | Atlantis | Denver colocation |

## Rack / Location Identifiers

Rack IDs are scoped per-site — `r01` at Fairy is a different rack than `r01`
at Atlantis. The site prefix in the device name disambiguates.

| Identifier | Meaning |
|------------|---------|
| `r##` | Numbered server/compute rack |
| `mdf` | Main distribution frame (network rack) |

## Role Abbreviations

| Abbreviation | Meaning | Example |
|--------------|---------|---------|
| `cn` | Compute node | fairy-r02-cn01 |
| `dgx` | DGX Spark GPU node | fairy-r02-dgx01 |
| `gw` | Gateway / router | fairy-gw01 |
| `tor` | Top-of-rack switch | fairy-r02-tor01 |
| `asw` | Access switch | fairy-mdf-asw01 |
| `msw` | Management switch | fairy-r02-msw01 |
| `fsw` | Fabric switch | fairy-r02-fsw01 |
| `vsw` | PoE / video switch | fairy-mdf-vsw01 |
| `ups` | Uninterruptible power supply | fairy-r02-ups01 |
| `pdu` | Power distribution unit | fairy-r02-pdu01 |
| `store` | Storage appliance | fairy-store01 |
| `nvr` | Network video recorder | fairy-nvr01 |
| `core` | Core switch | atlantis-r01-core01a |

## Cluster Names

Kubernetes clusters follow `{site}-k8s{##}`:

| Cluster | Site |
|---------|------|
| fairy-k8s01 | Fairy |
| atlantis-k8s01 | Atlantis |

## BMC / IPMI Names

Out-of-band management interfaces append `-mgmt` to the device name:

```text
{device-name}-mgmt
```

Since the site is already encoded in the device name, no additional site
suffix is needed.

Example: `atlantis-r01-compute01-mgmt` for the BMC of
atlantis-r01-compute01.

## Examples

| Name | Reads as |
|------|----------|
| `fairy-r02-cn03` | Fairy, rack 02, compute node 3 |
| `fairy-r02-dgx01` | Fairy, rack 02, DGX Spark node 1 |
| `fairy-mdf-asw01` | Fairy, MDF, access switch 1 |
| `fairy-r02-tor01` | Fairy, rack 02, top-of-rack switch 1 |
| `fairy-gw01` | Fairy, gateway 1 (site-level) |
| `fairy-store01` | Fairy, storage appliance 1 (site-level) |
| `fairy-k8s01` | Fairy, Kubernetes cluster 1 |
| `atlantis-r01-core01a` | Atlantis, rack 01, core switch 1a |
