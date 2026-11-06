# Dragonfly named recovery save

The original pre-upgrade Jobs in #3038 fail before SAVE because Dragonfly
v2.0.2 does not emit `run_id` in `INFO server`. Keep those Jobs and their
manifests as evidence. Updating their pod templates fails Kubernetes' immutable
field validation; a client image update does not repair them.

The two `queue/recovery-save-c694.yaml.template` files are **manual templates**, excluded
from Kustomize. Merging them does not run anything or restore Flux health.
They use a fresh Job name and the basename `c694-pre-v2-1`. Approval to publish
or merge this preparation is separate from approval to execute either SAVE.

## Before execution

Coordinate with the C-629 laptop session and obtain approval for each attempt.
Do one namespace at a time. Pause upgrades and any planned primary changes
through file verification and recovery capture. Preserve the failed Jobs,
existing snapshots and volumes. Do not delete, recreate or force-apply a Job.

From the laptop, select the current primary pod and record its UID, restart
count, creation time and owning PVC. Confirm authenticated ROLE is `master` and
`INFO server` provides numeric `uptime_in_seconds` of at least 180. Use the
existing Secret through `secretKeyRef`; never read or print its value.
Inspect the selected PVC's snapshot directory and verify **no**
`c694-pre-v2-1*` files exist. Stop if the Job name or basename has been used;
inspect its outcome rather than rerunning or overwriting evidence.

The script pins every connection to the selected pod's numeric IPv4 address,
not the primary Service. ROLE must remain master and uptime must not decrease.
The 180-second minimum exceeds the entire 120-second Job deadline, so a restart
during that window cannot pass the uptime check. These checks detect a restart
or role loss; they do not prevent one or prove that recovery files are complete.
Do not extend the deadline without revisiting this guard.

After execution approval, set `recovery_namespace` and `recovery_primary_pod`
locally to the approved namespace and pod. Render the exact target privately:

```sh
recovery_primary_ip=$(kubectl -n "$recovery_namespace" get pod "$recovery_primary_pod" -o jsonpath='{.status.podIP}')
kubectl create --dry-run=client \
  -f "kubernetes/apps/$recovery_namespace/queue/recovery-save-c694.yaml.template" -o json |
  jq --arg host "$recovery_primary_ip" \
    '(.spec.template.spec.containers[0].env[] | select(.name == "RECOVERY_HOST").value) = $host' \
  > "$TMPDIR/recovery-save-c694.json"
```

Verify the rendered namespace, new Job name, target, Secret reference and
script against the approved template. Recheck pod UID/restarts and primary
status immediately before `kubectl create -f "$TMPDIR/recovery-save-c694.json"`.
Use create, never apply/replace. The temporary file contains a target address,
not credentials; do not commit or paste it. The template intentionally refuses
to run until a numeric target is supplied. It has no automatic retries.

## Verify and finish

1. Inspect Job status and unfiltered stage logs. An interruption or failed
   postcondition can leave a completed SAVE: do not infer absence of files and
   do not retry automatically.
2. Recheck the recorded pod UID/restart count and ROLE. Inspect source logs for
   completion of the named SAVE. On that pod's PVC, verify the complete named
   summary and shard file set exists, is nonempty, and matches the successful
   save's shard count. Record names, sizes and timestamps privately; an `OK`
   alone is insufficient. Do not treat a partial set as recovery evidence.
3. Capture and retain the verified recovery set through C-629's approved
   recovery procedure before any upgrade. A named save on the live PVC alone
   is not an independent backup or proof that a restore works.
4. Only after both recovery sets are verified, prepare a separate reviewed
   Flux health change for the retained failed Jobs. This preparation deliberately
   leaves their health failures visible until recovery evidence exists. Keep
   their immutable pod templates unchanged, including during dependency bumps.

If any check fails, keep all Jobs/files and return the evidence to C-694/C-629.
There is no destructive rollback for this preparation; stop before creating
the next Job. No upgrade is authorized by these templates.

Local fault-injection checks: `python3 scripts/tests/test-dragonfly-recovery-save.py`.
