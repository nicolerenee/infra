---
description: Freckle Node — custom-built compute node purpose-built for homelab Kubernetes clusters
---

# Freckle Node

The Freckle Node is a custom-built rackmount compute node purpose-built
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
| Cooler | Thermalright AXP90-X53 Full (copper) | Low-profile for 2U clearance, 145W TDP rating |
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

- Chassis: delivered; fairy-r02-cn02 built 2026-09-27 (BIOS 2.0, replaces
  fairy-compute02 as the third control-plane node)
- RAM: on hand
- CPUs: 265K thermal test on cn01 (Sliger CX2151, AXP90-X53 Full) hit the
  105 °C Tjmax within a minute at stock power limits. The chassis' 66 mm cooler
  ceiling rules out a bigger heatsink, so the fix is a BIOS power-limit cap
  (see below) rather than the 65 W 265 non-K.

### BIOS and BMC baseline

New X14SAZ boards ship with BIOS 2.0 (02/2026), whose defaults differ from the
1.1a boards in ways that break a Talos bring-up. Fix these **before** booting
the Talos ISO; read/push them over Redfish once the BMC is licensed.

#### Settings that differ from BIOS 2.0 defaults

| Attribute | Value | Why |
|-----------|-------|-----|
| `PrimaryDisplay` | `Auto` | 2.0 defaults to `IGFX`, which hands the kernel an iGPU framebuffer. systemd-boot still shows on the BMC KVM, then the console goes black the moment Talos starts and never comes back. |
| `Re_SizeBARSupport` | `Enabled` | matches cn01 |
| `SR_IOVSupport` | `Enabled` | matches cn01; VF NICs for KubeVirt |
| `ACPISleepState` | `Suspend Disabled` | server, never sleeps |
| `OnboardLAN1Support`, `OnboardLAN2Support` | `Disabled` | the two i226 2.5G ports are unused; only the X550 pair (LAN3/LAN4 → `eno3`/`eno4`) is cabled |
| `TPMDeviceSelection` | `dTPM` | Talos disk encryption seals to the discrete TPM |
| `SecureBootMode` | `Custom` | Sidero's keys enrolled, see below |
| `PowerLimit1Override` / `PowerLimit1` | `Enabled` / `125000` | milliwatts. Caps the 265K at its 125 W TDP |
| `PowerLimit2Override` / `PowerLimit2` | `Enabled` / `150000` | stock PL2 is 250 W, which a 150 W-class low-profile cooler cannot sink |

The full cn01 attribute set (248 keys) is the reference; diff a new node
against it rather than trusting defaults.

#### Reading and pushing BIOS settings over Redfish

Supermicro gates the BIOS endpoints behind a node-locked **SFT-DCMS** license.
Buy one per node up front (Supermicro Store); without it `GET
/redfish/v1/Systems/1/Bios` returns `403 Not licensed`. With it:

```bash
# read
curl -sk -u "$USER:$PASS" https://<bmc>/redfish/v1/Systems/1/Bios | jq .Attributes
# stage changes (applied at next POST)
curl -sk -u "$USER:$PASS" -X PATCH -H 'Content-Type: application/json' \
  https://<bmc>/redfish/v1/Systems/1/Bios/SD \
  -d '{"Attributes":{"PrimaryDisplay":"Auto","PowerLimit1Override":"Enabled","PowerLimit1":125000}}'
# apply
curl -sk -u "$USER:$PASS" -X POST -H 'Content-Type: application/json' \
  https://<bmc>/redfish/v1/Systems/1/Actions/ComputerSystem.Reset -d '{"ResetType":"ForceRestart"}'
```

Allowed values and units are in the registry at
`https://<bmc>/registries/BiosAttributeRegistry.1.0.0.json`. Redfish only
inventories the BMC's own NIC on these boards; host NIC MACs come from the
Talos dashboard or the switch, not the BMC.

#### BMC network mode: Dedicated, not Failover

Supermicro's default `Failover` mode lets the BMC take over a host LAN port via
NC-SI when its dedicated link drops. On the X14SAZ the shared port is one of
the **X550 10G ports**. During cn02's bring-up the BMC grabbed the switch port
at 100 Mbps while the host was down, and after switching the BMC to
`Dedicated` that switch port stayed dead (LED lit, controller reporting it
down) through a host cold cycle. Moving the cable to a fresh port linked at 10G
immediately. Set `LAN Interface: Dedicated` in the BMC before first boot.

#### Secure Boot key enrollment

The Talos secureboot ISO and installer are signed with Sidero's key. A fresh
board only trusts Microsoft's, and Supermicro firmware rejects the image
silently (black screen, no error). One-time per board:

1. BIOS → Security → Secure Boot: mode `Custom`, then reset to **Setup Mode**
   (erase keys). Leave Secure Boot enabled.
2. Boot the Talos secureboot ISO. Auto-enrollment only happens inside a
   hypervisor, so press `Esc` at the systemd-boot menu and choose
   **Enroll Secure Boot keys: auto**.
3. It enrolls PK/KEK/db and reboots into the UKI under Secure Boot.

`talosctl get securitystate` on a booted node should report `secureBoot: true`
and `bootedWithUKI: true`.
