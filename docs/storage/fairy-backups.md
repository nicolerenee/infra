---
description: How fairy-k8s01 backs up app PVCs — VolSync rsync-tls mirrors into per-app ZFS datasets on fairy-store01, ZFS snapshots provide history, ZFS replication provides off-site
---

# Fairy Backups (VolSync rsync-tls + ZFS)

fairy-k8s01 backs up application PVCs by mirroring them with VolSync's
rsync-tls mover into one NFS-backed ZFS dataset per app on `fairy-store01`.
History comes from ZFS snapshots on the NAS and off-site from ZFS replication
to `atlantis-store01`; no restic repository or rest-server is involved.

## How it fits together

```text
app PVC (ceph-block)
  └─ ReplicationSource  — hourly: CSI snapshot, rsync delta over TLS
       └─ ReplicationDestination — persistent listener in the app namespace
            └─ <app>-backup PVC   — truenas-nfs-backup StorageClass (Retain)
                 └─ vault01/kubernetes/backups/fairy-k8s01/pvc-<uuid>  (ZFS dataset)
                      ├─ periodic snapshot tasks  (history + retention)
                      └─ replication task         (off-site, atlantis-store01)
```

Pieces in the repo:

| Piece | Location |
|---|---|
| TrueNAS CSI driver | `kubernetes/apps/storage/truenas-csi/`, pointer `clusters/fairy-k8s01/apps/truenas-csi/` |
| StorageClasses `truenas-nfs`, `truenas-nfs-backup` | `kubernetes/apps/storage/truenas-csi/storageclasses.yaml` |
| VolSync operator | `kubernetes/apps/storage/volsync/`, pointer `clusters/fairy-k8s01/apps/volsync-system/` |
| snapshot-controller + `csi-ceph-blockpool` class | `clusters/fairy-k8s01/apps/kube-system/snapshot-controller.yaml` |
| Per-app component | `kubernetes/components/volsync-rsync-tls/` |

The restic-based component (`kubernetes/components/volsync`) is atlantis-only.

## Why this design

- **The backup target is outside the cluster's failure domain.** The data
  lands on local ZFS on the NAS; the cluster only ever holds a client.
- **History is immutable from the client's side.** A compromised or
  misconfigured cluster can overwrite the mirror but cannot delete a ZFS
  snapshot. Restic's append-only mode only approximates this.
- **Off-site is a ZFS replication task,** not a second backup system.
  Incremental sends carry the full snapshot history to `atlantis-store01`.
- **Files are browseable** on the NAS, and every retention point is under
  `.zfs/snapshot/` inside the dataset.
- **Nothing to operate** beyond the NAS tasks: no restic server, no repo
  pruning, no lock cleanup.

The trade: there is no in-cluster "restore into a new PVC" primitive, so a
restore is a runbook (below), and there is no cross-app deduplication.

## Using the component

Include it from the app's `kustomization.yaml` and set the substitutions on
the cluster pointer:

```yaml
# kubernetes/apps/<category>/<app>/kustomization.yaml
components:
  - ../../../components/volsync-rsync-tls
```

```yaml
# kubernetes/clusters/fairy-k8s01/apps/<ns>/<app>.yaml
spec:
  postBuild:
    substitute:
      APP: paperless
      VOLSYNC_UID: "1000"      # the app's runAsUser
      VOLSYNC_CAPACITY: 50Gi
      VOLSYNC_SCHEDULE: "12 * * * *"   # pick a distinct minute per app
```

The app mounts the live PVC with `existingClaim: ${APP}`. The component
provides the live PVC, the `<app>-backup` PVC, and the source/destination
pair. VolSync generates the TLS pre-shared key on the destination
(`volsync-rsync-tls-<app>`) and the source references it by name.

Check a backup:

```bash
kubectl -n <ns> get replicationsource <app> \
  -o jsonpath='{.status.lastSyncTime} {.status.latestMoverStatus.result}{"\n"}'
```

## NAS layout (fairy-store01, pool vault01)

| Dataset | Purpose | Managed by |
|---|---|---|
| `vault01/kubernetes/nfs/<pv>` | general RWX volumes (`truenas-nfs`, reclaim Delete) | CSI driver |
| `vault01/kubernetes/block/<pv>` | future iSCSI / NVMe-oF zvols | CSI driver |
| `vault01/kubernetes/backups/<cluster>/<pv>` | backup mirrors (`truenas-nfs-backup`, reclaim Retain) | CSI driver |

The driver creates intermediate datasets as needed and names each volume
after its PV (`pvc-<uuid>`). To find an app's dataset:

```bash
kubectl -n <ns> get pvc <app>-backup -o jsonpath='{.spec.volumeName}{"\n"}'
```

`vault01/kubernetes/backups` is an encrypted dataset (AES-256-GCM, key-based so
it unlocks at boot); children inherit the encryption. The recovery copy of
the key is the GSM secret `fairy-store01-backups-zfs-key`. The driver
authenticates as the least-privilege TrueNAS user `truenas-csi` (dataset,
snapshot, snapshot-task and sharing roles only).

Snapshot and replication tasks are configured on the NAS, recursively, so
new apps are covered without touching the NAS. The per-volume `snapshot.*`
StorageClass parameters are intentionally unused: they would create one
snapshot task per PVC.

| Task | Dataset | Schedule | Keep |
|---|---|---|---|
| hourly snapshots (pool-wide, pre-existing) | `vault01` | :47 | 2 days |
| daily snapshots (pool-wide, pre-existing) | `vault01` | 02:23 | 2 weeks |
| weekly snapshots | `vault01/kubernetes/backups` | Sun 03:00 | 3 months |
| replication to `atlantis-store01` | `vault01/kubernetes/backups` | TODO | raw send, keeps encryption |

Files in a backup dataset are owned `root:<app gid>` because the NFS export
squashes all client access to root (`mapall`). That is fine for a mirror;
a restore runs as the app's UID and produces files it owns.

## Restore runbook

1. Identify the dataset (command above) and pick a snapshot on the NAS:
   `zfs list -t snapshot vault01/kubernetes/backups/fairy-k8s01/pvc-<uuid>`.
2. Scale the app to zero so nothing writes to the live PVC.
3. If the live PVC itself is lost, let Flux recreate it empty (it is
   prune-disabled, so only `kubectl delete pvc` removes it).
4. Run a one-off Job in the app's namespace, as the app's UID, that mounts
   the `<app>-backup` PVC read-only and the live PVC read-write, and copies
   from `.zfs/snapshot/<name>/` (or the dataset root for the latest mirror)
   into the live PVC with `rsync -a --delete`.
5. Scale the app back up and verify, then delete the Job.

For a whole-cluster rebuild the `<app>-backup` PVC is gone with the cluster
but the dataset is not: create a static PV for `csi.truenas.io` pointing at
the existing dataset, bind the `<app>-backup` PVC to it, then follow the
steps above. Pausing the app's ReplicationSource (`spec.paused: true`) until
the restore is verified prevents the next scheduled sync from mirroring an
empty PVC over the backup.

## PostgreSQL (CNPG) backups

CNPG clusters on fairy back up through the barman-cloud plugin into a
bucket on the in-cluster Ceph RGW (an ObjectBucketClaim per cluster, so the
credentials never leave the cluster), and an rclone CronJob mirrors that
bucket into a `truenas-nfs-backup` PVC every 15 minutes. From there the
same ZFS snapshot and replication tasks apply. A cluster loss therefore
costs at most one mirror interval of WAL.

| Piece | Location |
|---|---|
| plugin | `kubernetes/apps/database/cloudnative-pg/barman-plugin/`, pointer `clusters/fairy-k8s01/apps/db/barman-plugin.yaml` |
| pg-18a cluster, ObjectStore, ScheduledBackup, mirror | `clusters/fairy-k8s01/apps/db/pg-clusters/pg-18a-*.yaml` |

Base backups run every 6 hours (the ScheduledBackup cron is six fields,
seconds first); point-in-time granularity comes from WAL archiving. Bucket
retention is 30 days; the mirror follows the bucket, and ZFS snapshots keep
the longer tail.

### Restore after a cluster rebuild

1. Deploy the plugin and the OBC so the bucket exists again (it will be
   empty).
2. Run the mirror in reverse from a one-off pod with the mirror PVC
   mounted: `rclone sync /mirror rgw:pg-18a-backups`. To restore to an
   older point, copy from `.zfs/snapshot/<name>/` instead of the live
   mirror.
3. In `pg-18a-cluster.yaml`, uncomment `bootstrap.recovery` and
   `externalClusters` pointing at the previous `serverName`, and bump the
   cluster's own `serverName` suffix so the new archive doesn't collide.
4. After the cluster is healthy, remove the bootstrap block.

## Operating notes

- Verified 2026-10-13 on fairy: two consecutive syncs of a test PVC landed
  with matching checksums and symlinks intact, into an encrypted child
  dataset with a 1 GiB quota and an export limited to the compute VLAN.
- On Talos the chart's node DaemonSet needs its `/etc/iscsi` hostPath
  relocated (see the postRenderer in the HelmRelease) or every node pod
  stays in ContainerCreating.
- NFS mounts use `hard,nfsvers=4.1`; a NAS outage stalls the destination
  mover rather than corrupting anything, and the ReplicationSource reports
  the failed sync.
- The `truenas-nfs-backup` class is `Retain`: deleting a PVC leaves the
  dataset and its snapshots on the NAS. Remove datasets on the NAS
  deliberately, never by deleting the PVC.
- Capacity on the backup PVC is a ZFS quota on the dataset; grow it with the
  PVC (`allowVolumeExpansion`).
