---
# Per-node opt-in to sandboxd workload isolation (topf.yaml `data.workloadIsolation`).
# Overrides the cluster-wide `false` in all/01-cluster.yaml; later directories win.
# Fresh installs get it from day one; in-place-upgraded nodes are flipped one at a
# time once the NVIDIA stack is proven on the new sparks.
apiVersion: v1alpha1
kind: SecurityProfileConfig
workloadIsolation: {{ if and (hasKey .Node.Data "workloadIsolation") .Node.Data.workloadIsolation }}true{{ else }}false{{ end }}
