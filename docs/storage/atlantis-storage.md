---
description: How atlantis-k8s01 uses atlantis-store01 through the TrueNAS CSI driver — SSD iSCSI for latency-sensitive app state, NFS rsync-tls backups on the HDD pool — and the 2026-10-19 benchmarks behind it
---

# Atlantis Storage (TrueNAS CSI + benchmarks)

atlantis-k8s01 provisions volumes on `atlantis-store01` with the TrueNAS CSI
driver (`csi.truenas.io`): iSCSI zvols on the SSD pool for latency-sensitive
app state, and NFS datasets on the HDD pool for VolSync rsync-tls backups.
The choice rests on the benchmarks below, which also explain why media scans
are slow.

## What runs where

| Piece | Where |
|---|---|
| Driver (shared with fairy) | `kubernetes/apps/storage/truenas-csi/`, pointer `clusters/atlantis-k8s01/apps/truenas-csi/truenas-csi.yaml` |
| `truenas-iscsi` StorageClass (atlantis only) | `clusters/atlantis-k8s01/apps/truenas-csi/block/` |
| `truenas-nfs`, `truenas-nfs-backup` StorageClasses | shared dir, default pool `store01` (HDD) |
| `truenas-csi` VolumeSnapshotClass | shared dir (both clusters) |
| API key | GSM `atlantis-k8s01-truenas-csi`, via the `gcp-sm-cluster` ClusterSecretStore |

`democratic-csi` is still deployed but owns no StorageClass. It only serves
the volume it already provisioned (`nas-garage`) until that is migrated.

## NAS layout (atlantis-store01)

| Dataset | Purpose |
|---|---|
| `ssdstore01/kubernetes/block/<pv>` | `truenas-iscsi` zvols (sparse, LZ4), SSD mirrors |
| `store01/kubernetes/backups/atlantis-k8s01/<pv>` | rsync-tls backup mirrors (`truenas-nfs-backup`, reclaim Retain) |
| `store01/kubernetes/nfs/<pv>` | general RWX volumes (`truenas-nfs`) |

- `store01/kubernetes/backups` is encrypted (AES-256-GCM, key-based so it
  unlocks at boot). The recovery copy of the key is GSM
  `atlantis-store01-backups-zfs-key`.
- The driver authenticates as the least-privilege TrueNAS user `truenas-csi`
  (dataset, snapshot, snapshot-task, NFS, iSCSI and NVMe-oF sharing roles).
- Recursive snapshot tasks on `store01/kubernetes/backups`:

| Task | Schedule | Keep |
|---|---|---|
| hourly | :47 | 2 days |
| daily | 02:23 | 2 weeks |
| weekly | Sun 03:00 | 3 months |

- NFS service has v3 and v4 enabled. The shared NFS classes mount with
  `nfsvers=4.1`; with only v3 enabled the mount hangs in ContainerCreating.

## Using it for an app

Same component as fairy (see [Fairy Backups](fairy-backups.md)), with the
live PVC on the SSD class:

```yaml
# kubernetes/clusters/atlantis-k8s01/apps/<ns>/<app>.yaml
spec:
  components:
    - ../../../components/volsync-rsync-tls
  postBuild:
    substitute:
      APP: <app>
      VOLSYNC_UID: "3000"
      VOLSYNC_CAPACITY: 100Gi
      VOLSYNC_SCHEDULE: "41 * * * *"
      VOLSYNC_STORAGE_CLASS: truenas-iscsi
      VOLSYNC_SNAPSHOT_CLASS: truenas-csi
```

## Benchmarks (2026-10-19, atlantis-compute04)

fio and SQLite from one pod, same node, 45 s runs.

| Test | ceph-block | truenas-iscsi | node NVMe |
|---|---|---|---|
| 4k sync write, fsync p50 / p99 | 22 / 45 ms | 3.6 / 7.6 ms | 2.7 / 5.9 ms |
| SQLite `synchronous=FULL` commits/s | 37 | 108 | 357 |
| SQLite WAL + `NORMAL` commits/s | 9,600 | 17,700 | 29,000 |
| 4k random read, QD1, IOPS | 1,300 | 5,800 | 15,000 |
| 70/30 mixed 4k, 8 jobs, read IOPS | 1,200 | 16,800 | 35,000 |
| 1M sequential write | 50 MB/s | 407 MB/s | 418 MB/s |

Atlantis Ceph is slow on synced writes because all nine OSDs are Samsung 860
EVO consumer SSDs without power-loss protection (~10 ms per commit, times three
replicas). That affects every `ceph-block` workload on atlantis.

### Media export (HDD pool)

The media export (`store01/warehouse20/media`, NFSv3) sits on three RAIDZ2
vdevs of ten HDDs with no special vdev or L2ARC, so random reads are
seek-bound:

| Test | Result |
|---|---|
| 4k random read, QD1 | 43 IOPS, 20 ms |
| 64k random read, 8 jobs | 170–330 IOPS (varies with NAS load) |
| File probe, 1 / 8 / 16 parallel | 13 / 33 / 39 files/s |
| Sequential stream | 411 MB/s |
| Directory walk with stat | 7,000–36,000 files/s (metadata in ARC) |

Client mount options were A/B tested (`nconnect=8`, `actimeo=600`, `nocto`)
and made no difference. `nconnect` is also per NFS client, meaning per server
address per node: the first mount on a node fixes the connection count and
later mounts inherit it. Faster scans need parallelism (8–16) or NAS-side
changes such as an L2ARC, not mount tuning.
