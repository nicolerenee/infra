---
description: Overview of the fairy site — primary homelab with compute rack, GPU nodes, and home network infrastructure
---

# Fairy Site

Fairy is the primary homelab site, with a 32U compute rack and a
wall-mounted MDF rack. It runs a single Kubernetes cluster (fairy-k8s01) across
custom-built AMD64 [Freckle Node](../../compute/freckle-node.md) compute nodes
and seven [NVIDIA DGX Spark](../../compute/dgx-spark.md) ARM64 GPU nodes, all on
Talos Linux. The compute nodes handle everything from home automation and media
services to monitoring and storage controllers, while the DGX Sparks run LLM
inference via vLLM. Storage is split between Ceph (distributed across the compute
nodes' NVMe OSDs) for Kubernetes workloads and a
[TrueNAS Mini-R](../../storage/truenas-mini-r.md) for bulk media.

The network is flat on a single /24 with a
Firewalla Gold Pro as the router, a 10G
top-of-rack switch for all node traffic, and a 400G fabric switch for GPU-to-GPU
communication. See [Fairy Network Topology](../../networking/fairy-network.md)
for the full picture.

## MDF

The main distribution frame rack sits behind the server rack and houses the
router, switches, and home network management.

### Rack Layout { #mdf-rack-layout }

[Tecmojo 9U Wall Mount Rack](https://www.amazon.com/dp/B0CCJ9ZZKL) (white,
glass front door).

![MDF rack diagram](rack-mdf.svg)

### Hardware { #mdf-hardware }

#### Networking { #mdf-networking }

| Device | Model | Function |
|--------|-------|----------|
| fairy-gw01 | Firewalla Gold Pro | Router / firewall, [AT&T 802.1X bypass](../../guides/att-802.1x-bypass.md) |
| fairy-mdf-asw01 | Cisco C1300X-24NGU-4X | Home network switch |
| fairy-mdf-vsw01 | Cisco C1300-8FP-2G | PoE switch - outdoor cameras (surge isolation) |
| WiFi APs (x3) | Firewalla Access Point 7 - Ceiling | WiFi AP |

The outdoor PoE switch (fairy-mdf-vsw01) is intentionally separate from the home
network to provide lightning/surge isolation for outdoor camera and AP cable
runs. It connects back to fairy-mdf-asw01 via fiber to maintain electrical isolation.

#### Power { #mdf-power }

| Device | Model | Notes |
|--------|-------|-------|
| fairy-mdf-pdu01 | CyberPower PDU81005 | Not network-connected |

## r02

The compute rack houses all Kubernetes nodes, storage, and the 10G/400G network
fabric for the fairy-k8s01 cluster.

### Rack Layout { #r02-rack-layout }

[StarTech 32U 4-Post Server Rack Cabinet](https://www.amazon.com/dp/B099986PZF)
(RK3236BKF) with adjustable mounting depth and glass front / mesh rear doors.

![Rack r02 diagram](rack-r02.svg)

The DGX Spark units sit on an 8-bay DGX shelf behind a front fan panel. They
originally sat in
[Racknex UM-NVI-202](https://racknex.com/nvidia-dgx-spark-rack-mount-kit-um-nvi-202/)
trays of two; the shelf replaced those in October 2026.

### Hardware { #r02-hardware }

#### Networking { #r02-networking }

| Device | Model | Function |
|--------|-------|----------|
| fairy-r02-tor01 | Netgear XS724EMv2 | Top-of-rack switch (24x 10GBase-T, 4x 10G SFP+) |
| r01-fsw01 | MikroTik CRS804-4DDQ | GPU fabric switch (4x 400G QSFP-DD, one 200G breakout leg per Spark) |
| fairy-r02-msw01 | Cisco Catalyst C1300-24T-4G | Out-of-band management (IPMI, JetKVM, PDU, vPro) |

See [Fairy Network Topology](../../networking/fairy-network.md) for port
allocations and IP addressing.

#### Compute { #r02-compute }

The Sparks use the bare host names they carry as Kubernetes nodes. Other
device names and the rack label on this page predate that naming and are
due a refresh.

| Device | Function | Type |
|--------|----------|------|
| fairy-r02-cn01 | Control plane + worker | [Freckle Node Gen 3.0](../../compute/freckle-node.md#gen-30) |
| fairy-r02-cn02 | Control plane + worker | [Freckle Node Gen 3.0](../../compute/freckle-node.md#gen-30) |
| fairy-r02-cn03 | Control plane + worker | [Freckle Node Gen 3.0](../../compute/freckle-node.md#gen-30) |
| fairy-r02-cn04 | Worker (planned) | [Freckle Node Gen 3.1](../../compute/freckle-node.md#gen-31-changes) |
| fairy-r02-cn05 | Worker (planned) | [Freckle Node Gen 3.1](../../compute/freckle-node.md#gen-31-changes) |
| fairy-r02-cn06 | Worker (planned) | [Freckle Node Gen 3.1](../../compute/freckle-node.md#gen-31-changes) |
| dgx01 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx02 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx03 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx04 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx05 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx06 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |
| dgx07 | GPU inference | [DGX Spark](../../compute/dgx-spark.md) |

#### Storage { #r02-storage }

| Device | Model | Notes |
|--------|-------|-------|
| fairy-store01 | [TrueNAS Mini-R](../../storage/truenas-mini-r.md) | 12x 26TB Exos, 2x 6-wide raidz2 |

#### Appliances { #r02-appliances }

| Device | Model | Function |
|--------|-------|----------|
| fairy-nvr01 | UNVR Pro | Network video recorder (7x 3.5" bays, 10G SFP+) |

#### Power { #r02-power }

| Device | Model | Function |
|--------|-------|----------|
| fairy-r02-ups01 | CyberPower PR3000RTXL2UHVACN | UPS (2U) |
| fairy-r02-pdu01–04 | CyberPower PDU81005 | Power distribution unit (0U, rear side rails) |

## Related Pages

- [Fairy Network Topology](../../networking/fairy-network.md) — topology
  diagram and IP addressing
- [AT&T 802.1X Bypass](../../guides/att-802.1x-bypass.md) — wpa_supplicant
  on Firewalla Gold Pro
- [Firmware Upgrades](../../runbooks/firmware-upgrades.md) — DGX Spark firmware
  updates via fwupd on Talos
- [Freckle Node](../../compute/freckle-node.md) — Gen 3.0 and 3.1 build
  specs, BOM, and design decisions
- [DGX Spark](../../compute/dgx-spark.md) — NVIDIA driver selection, GPU
  operator configuration
