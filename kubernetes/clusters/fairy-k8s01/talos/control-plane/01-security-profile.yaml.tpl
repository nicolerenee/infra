---
# Per-node opt-in to sandboxd workload isolation (topf.yaml `data.workloadIsolation`).
# Overrides the cluster-wide `false` in all/01-cluster.yaml; later directories win.
# The sparks were flipped first (ba78e229); the cn nodes follow one at a time,
# riding the reboot each already takes for the v1.14.2 / iommu=pt re-install.
apiVersion: v1alpha1
kind: SecurityProfileConfig
workloadIsolation: {{ if and (hasKey .Node.Data "workloadIsolation") .Node.Data.workloadIsolation }}true{{ else }}false{{ end }}
