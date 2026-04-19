---
description: Freckle Compute Nodes — custom-built compute nodes purpose-built for homelab Kubernetes clusters
---

# Freckle Compute Nodes

The Freckle Compute Nodes are custom-built rackmount compute nodes purpose-built
for running Kubernetes workloads across homelab clusters. Each generation is
designed around specific workload requirements, with minor revisions within a
generation for chassis or thermal changes.

## Generation 3

Generation 3 (2025) is a ground-up redesign driven by the need for Intel Arc
iGPU support for hardware-accelerated H.265 and 4K transcoding (Plex/Jellyfin).
These are the primary AMD64 workhorse nodes in the fairy-k8s01 cluster, running
all non-inference workloads: home automation, media services, networking, auth,
monitoring, and storage controllers.

Gen 3.1 (2026) is a minor revision that moves to a chassis with native U.2 drive
mounting support — in Gen 3.0 the drives are just loose inside the chassis.

### Gen 3.0

#### Bill of Materials

| Component | Part | Notes |
|-----------|------|-------|
| Motherboard | Supermicro X14SAZ-TLN4F | LGA1851, dual 10G X550 + 2x 2.5G i226LM + IPMI |
| CPU | Intel Core Ultra 7 265K | 20C/20T, 125W TDP, Arc iGPU |
| RAM | DDR5 4x32GB | 128GB total, see note below |
| OS Disk | Samsung 980 Pro M.2 | Boot drive (JMD1 slot) |
| Ceph OSDs | 2x Samsung SZ1735 1.6TB U.2 | SLC, 30 DWPD, 250K rand write IOPS |
| MCIO Cable | 10Gtek MCIO x8 to 2x U.2 | SFF-TA-1016 to SFF-8639, 0.75m, PCIe 4.0 |
| NIC | Onboard Intel X550 10GBase-T | Dual-port, second port available for dedicated Ceph traffic |
| Chassis | Sliger CX2151a 2U | Single PCIe riser (double-width), SFX PSU |
| Fans | 4x Arctic P8 Max 80mm | Chassis fans |
| Rails | iStarUSA TC-RAIL-20 | 20" sliding rail kit |
| Cooler | Thermalright AXP90-X53 | Low-profile for 2U clearance |
| PSU | Corsair SF750 SFX | 750W |

#### Key Design Points

**Motherboard**: The Supermicro X14SAZ-TLN4F was chosen for its combination of
dual onboard Intel X550 10GBase-T, IPMI/BMC for remote management, and Intel
Arc iGPU for hardware transcoding (Plex/Jellyfin).

**Ceph OSD connectivity**: The two U.2 drives connect via the JNVME1 MCIO
connector (PCIe 4.0 x4+x4) using a breakout cable — no PCIe slot consumed. The
Samsung SZ1735 drives are SLC with 30 DWPD endurance, chosen for Ceph write
amplification tolerance.

**RAM**: Nodes use either Corsair CMK64GX5M2B6000Z40 or G.Skill F5-6000J4048F32GX2-FX5
kits (2x32GB each, two kits per node). Both are DDR5-6000 CL40 and run at
4400 MT/s when all four DIMM slots are populated.

**Network**: The onboard dual-port Intel X550 provides two 10GBase-T connections.
One port handles primary cluster traffic, with the second available as a
dedicated Ceph cluster network if needed.

#### Talos Extensions

| Extension | Purpose |
|-----------|---------|
| `siderolabs/i915` | Intel Arc iGPU support (media transcoding) |
| `siderolabs/intel-ucode` | CPU microcode updates |
| `siderolabs/iscsi-tools` | iSCSI client |
| `siderolabs/lldpd` | LLDP discovery |
| `siderolabs/mei` | Management Engine Interface |

### Gen 3.1 Changes

The Gen 3.1 nodes share the same motherboard, RAM, Ceph drives, and MCIO cable
as Gen 3.0. The differences are:

| Component | Gen 3.0 | Gen 3.1 |
|-----------|------|------|
| CPU | Core Ultra 7 265K (125W) | TBD — 265K or 265 non-K (65W) |
| Chassis | Sliger CX2151a | Sliger CX2151x |

#### Chassis

The Gen 3.1 nodes use the Sliger CX2151x. Note: three CX2130x chassis were
originally ordered by mistake — contacting Sliger to change to CX2151x.

#### CPU

The CPU choice depends on thermal validation. The 265K (125W TDP) would make a
fully homogeneous fleet with Gen 3.0, but needs to run cool enough in the CX2151x
with 3–4 fans. If thermals are marginal, the 265 non-K (65W TDP) provides
identical core count at lower power. Testing is scheduled for the first chassis
delivery.

#### Status

- Chassis: ordered (2–3 week lead time from Sliger)
- RAM: on hand
- CPUs: pending thermal validation
