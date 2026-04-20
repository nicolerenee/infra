---
description: iXsystems TrueNAS Mini-R — 2U rackmount NAS with 12 hot-swap bays, dual 10GbE, and IPMI
---

# TrueNAS Mini-R

The [TrueNAS Mini-R](https://www.truenas.com/truenas-mini/) is a 2U rackmount
NAS appliance from iXsystems. It's the rack-mountable member of the TrueNAS Mini
family, designed for small office and homelab use with enterprise-grade ZFS
storage features.

## Hardware

- **Form Factor**: 2U rackmount, 21" deep (short-depth)
- **CPU**: Intel Atom C3758, 8-core
- **RAM**: Up to 64GB DDR4 ECC
- **Drive Bays**: 12x 3.5" hot-swap (lockable), supports SATA HDD or SSD
- **Networking**: 2x 10GbE RJ45 (onboard), optional 2x 10GbE SFP+ add-in card
- **Management**: IPMI out-of-band management port
- **OS**: TrueNAS CORE (FreeBSD) or TrueNAS SCALE (Debian Linux)

## fairy-store01

fairy-store01 is the TrueNAS Mini-R at the fairy site, running TrueNAS SCALE.
It provides bulk media storage, Time Machine backups, and SMB shares for the
home network.

### Storage Layout

- **Drives**: 12x 26TB Seagate Exos
- **Pool Layout**: 2x 6-wide raidz2 vdevs
- **Usable Capacity**: ~208TB

### Network

- **Uplink**: 10G copper to fairy-r02-tor01 (Netgear XS724EMv2)

### Uses

- Media libraries (Plex, Jellyfin) via NFS exports to Kubernetes
- Time Machine backups
- SMB shares for general file storage
