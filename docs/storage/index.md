---
description: Storage systems — Ceph distributed storage and TrueNAS appliances
---

# Storage

Storage infrastructure for Kubernetes workloads and bulk media.

- [Ceph Benchmarking](ceph-benchmarking.md) — fio recipes for characterizing
  RBD performance, expected numbers, and the pitfalls that make naive runs
  read low
- [TrueNAS Mini-R](truenas-mini-r.md) — 2U rackmount NAS; fairy-store01 runs
  12x 26TB drives in dual raidz2
- [Fairy Backups](fairy-backups.md) — VolSync rsync-tls into per-app ZFS
  datasets on fairy-store01; ZFS snapshots for history, replication for
  off-site
- [Atlantis Storage](atlantis-storage.md) — TrueNAS CSI on atlantis-store01:
  SSD iSCSI for app state, rsync-tls backups on the HDD pool, and the
  benchmarks behind it
