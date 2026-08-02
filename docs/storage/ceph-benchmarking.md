---
description: How to benchmark Ceph RBD performance from a Kubernetes client with fio, what numbers to expect from this cluster, and the common gotchas that make naive runs misleading
---

# Ceph RBD benchmarking

How to characterize Ceph RBD performance from a Kubernetes pod with `fio`,
what targets to expect on this hardware, and the setup mistakes that make
naive runs read low without telling you why.

## When to run

- After hardware changes that could move the floor (NIC upgrade, new OSD
  hardware, replication factor change, network re-cabling).
- Before/after Ceph version bumps if perf is in question.
- To validate a perf regression complaint is real, not a one-off.
- To establish a baseline before tuning (so you can prove tuning helped).

Do **not** rely on a mixed `randrw` from a single client at a single block
size to characterize the cluster — see [Common pitfalls](#common-pitfalls).

## Methodology

Run **separate fio jobs** for each metric. Mixing read+write or sizes in one
run gives you a number that doesn't compare to anything.

The four axes that matter:

| Axis | What it measures | Test |
|---|---|---|
| Read IOPS | Small random read ceiling | 4K randread, high QD |
| Write IOPS | Small random write ceiling (replication-bound) | 4K randwrite, high QD |
| Read BW | Sequential read ceiling (network-bound) | 1M seqread, moderate QD |
| Write BW | Sequential write ceiling (network + replication) | 1M seqwrite, moderate QD |

Read IOPS is the easy ceiling — primary OSD responds, done. Write IOPS is
the *interesting* one: every write goes to all replicas, so write IOPS at
3x replication costs ~3x the cluster work of a read. That's where you'll see
network bottlenecks first.

## Cluster expectations

NVMe-only Ceph cluster, replication=3, healthy 10 GbE+ inter-OSD network,
single client to a single RBD image:

| Test | Reasonable range |
|---|---|
| 4K randread, QD=64 numjobs=4 | 30k–80k IOPS |
| 4K randwrite, QD=64 numjobs=4 | 10k–25k IOPS |
| 1M seqread, QD=32 | ~80–95% of network line rate |
| 1M seqwrite, QD=32 | ~30–45% of network line rate (3x replication) |
| Avg read latency | 1–3 ms |
| Avg replicated write latency | 3–8 ms |

A single client at single QD can never hit cluster max — these are
"reasonable single-client" numbers, not cluster aggregate. To exercise the
cluster ceiling, run the same fio Job from 3–4 pods on different nodes in
parallel and sum the results.

If single-client numbers come back **5–10× low** with **5–10× high latency**,
the bottleneck is almost always the network, not the OSDs. Verify the path:

```bash
# From the test pod's node, check the link to a remote OSD
ip -s link show $iface
ethtool $iface | grep Speed
```

On fairy specifically: cn02, cn03, and the DGX Sparks are on a transient
**1 GbE** uplink while r02-tor01 cabling is being migrated. Until that
migration completes, benchmarks from cn01 against OSDs on those nodes will
be capped at ~80–110 MiB/s of effective throughput regardless of the
cluster's actual capability.

## Test pod setup

Diagnostic namespace + a single PVC + Job. Adjust `nodeSelector` to pin to
the node you're characterizing.

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: ceph-bench
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bench
  namespace: ceph-bench
spec:
  storageClassName: ceph-block
  volumeMode: Block
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 50Gi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ceph-bench
  namespace: ceph-bench
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/hostname: fairy-r02-cn01    # change me
      tolerations:
        - operator: Exists
      containers:
        - name: fio
          image: alpine:3.20
          command: ["/bin/sh", "-euc"]
          args:
            - |
              set -eu
              apk add --no-cache fio >/dev/null
              # Pre-fill the device so reads don't hit zero-deduped pages.
              fio --name=prefill --filename=/dev/block --rw=write \
                  --bs=1M --iodepth=8 --numjobs=2 --size=20G \
                  --ioengine=libaio --direct=1 --group_reporting

              run() {
                echo "=== $1 ==="
                fio --name="$1" --filename=/dev/block \
                    --ioengine=libaio --direct=1 --time_based \
                    --runtime=120 --group_reporting \
                    --output-format=normal "${@:2}"
                echo
              }

              # Read IOPS ceiling
              run randread-4k --rw=randread --bs=4k --iodepth=64 --numjobs=4
              # Write IOPS ceiling
              run randwrite-4k --rw=randwrite --bs=4k --iodepth=64 --numjobs=4
              # Read BW ceiling
              run seqread-1m --rw=read --bs=1M --iodepth=32 --numjobs=1
              # Write BW ceiling
              run seqwrite-1m --rw=write --bs=1M --iodepth=32 --numjobs=1

              echo "== done $(date -u +%FT%TZ) =="
          volumeDevices:
            - { name: bench-pvc, devicePath: /dev/block }
      volumes:
        - name: bench-pvc
          persistentVolumeClaim:
            claimName: bench
```

Use `volumeMode: Block` and `--direct=1` so you measure RBD, not the host
page cache. The prefill pass writes real data so reads hit allocated extents
instead of getting served zero-fill from object thin-provisioning.

### Cluster-aggregate variant

To exercise the whole cluster, duplicate the Job pinned to a different node
per copy (cn01, cn02, cn03, dgx01…) and run them simultaneously. Sum the
read/write IOPS and BW from each pod's output. That's your cluster ceiling
for the workload mix.

## Reading the results

The output sections that matter:

```text
read: IOPS=NNNN, BW=XX MiB/s
  clat percentiles (usec): 50.00th, 99.00th, 99.99th
```

- **IOPS / BW** — the headline numbers.
- **clat p50** — median latency. Should be tight on NVMe (1–3 ms read).
- **clat p99 / p99.99** — tail latency. A wide gap from p50 means
  contention somewhere (network queue, OSD WAL flush, deep PG queue).

`slat` (submission latency) is rarely interesting — that's kernel overhead
before the IO is in flight.

## Common pitfalls

- **Mixed `randrw` in one fio job**: reads and writes contend on the same
  queue and saturate the wrong resource first. Always split.
- **No `--direct=1`**: the host page cache absorbs the IO and you measure
  RAM, not Ceph.
- **No prefill on a `volumeMode: Block` PVC**: reads against unwritten
  thin-provisioned blocks return zero-fill instantly with no OSD round
  trip. Numbers look unrealistically high.
- **Single QD, single job**: leaves the cluster idle. Use enough
  concurrency (numjobs × iodepth ≥ 64) to actually exercise the PGs.
- **Network-bottlenecked node**: a single link at 1 GbE caps everything,
  but the symptom looks like "slow OSDs" or "high latency." Always check
  the link speed of the client and the OSDs being read from.
- **Comparing across runs without holding everything else constant**:
  Ceph perf moves with deep scrub state, OSD compaction, even time of day.
  Run baseline and "after" within a short window for a fair compare.

## Cleanup

```bash
kubectl delete ns ceph-bench
```

The PVC is deleted with the namespace; the underlying RBD image is reclaimed
by `rook-ceph` shortly after.
