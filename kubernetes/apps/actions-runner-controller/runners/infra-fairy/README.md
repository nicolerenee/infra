# Package clients on fairy ARC

This overlay gives the runner and Kubernetes job containers the same Go,
checksum database, npm and Python package defaults. The shared runner base
continues to serve atlantis without a dependency on the fairy service.
Private Go modules bypass the package proxy; it has no Git credentials.

The hook adds a label to job pods so the package proxy admits their downloads.
The hook ConfigMap is mounted read-only; package clients receive URL settings
from a separate ConfigMap, with no credentials or shared writable cache.

These are defaults, not egress enforcement. Workflow and step environment,
explicit registry or index options, npm lockfile artifact URLs, and additional
Python indexes can select another source. Workflows using the cache should
keep these defaults, regenerate npm lockfiles against the cache, and avoid
extra indexes. Container environment takes precedence over envFrom. Toolchain
and action downloads are separate from package downloads.

After rollout, verify both a job without a container and a Kubernetes job
container: inspect the effective client settings, use empty client caches for
Go modules plus sumdb, npm ci and pip install, and correlate requests with
package-proxy logs. Revert the fairy Flux path and the job-pod ingress selector
to roll back; no cache data needs deleting.

The `Package Proxy Smoke` workflow runs on changes to its workflow or composite
action on main, and can also be dispatched manually. It checks inherited defaults
and exercises public Go with sumdb, npm ci and pip in separate host and Kubernetes
container jobs with fresh client caches. It uses no repository secrets. Correlate
its UTC start/end markers with proxy access logs; a green job alone does not prove
replica failover. Toolchain setup downloads are outside the package smoke check.
