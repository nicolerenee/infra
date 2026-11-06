# Node-local seccomp profiles

Talos installs each entry of `machine.seccompProfiles` (declared in
`../all/10-machine.yaml`) as `/var/lib/kubelet/seccomp/profiles/<name>` on every
node. Pods select one with:

```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/<name>
```

Rolling a profile out is a machine-config apply with topf on the affected nodes;
`seccompProfiles` needs no reboot.

## `runtime-default-userns.json`

Why: Steam runs games inside bubblewrap (pressure-vessel), which creates its
own user, PID, IPC, UTS and network namespaces and then mounts proc, tmpfs and
bind mounts inside them. containerd's `RuntimeDefault` only allows namespace
creation and mount syscalls to containers that hold `CAP_SYS_ADMIN`, so under a
pod user namespace (`hostUsers: false`) with every capability dropped,
bubblewrap fails at namespace creation. Steam's web helper (its whole UI is a
Chromium renderer) runs inside that bubblewrap and brings Chromium's own
sandbox: the zygote process creates a further user namespace and chroots to an
empty directory in it, which `RuntimeDefault` only allows to containers that
hold `CAP_SYS_CHROOT`. The alternative, `Unconfined`, removes the whole filter;
this profile keeps it and opens only what those two sandboxes need.

What it is: containerd 2.3.7's RuntimeDefault profile, as generated for a
container whose bounding capability set is empty, with these changes and no
others:

| Change | Reason |
| --- | --- |
| `clone`: the flag filter that rejected namespace flags is removed | namespace creation |
| `clone3`: the ENOSYS stub (which made glibc fall back to `clone`) is removed; allowed | namespace creation |
| `unshare`, `setns` allowed | bubblewrap creates and joins namespaces |
| `mount`, `umount2`, `pivot_root` allowed | bubblewrap's bind, remount, proc, tmpfs and root switch inside its mount namespace |
| `sethostname` allowed | bubblewrap `--hostname` in its own UTS namespace |
| `chroot` allowed | Chromium's zygote inside bubblewrap chroots to an empty directory (`/proc/self/fdinfo/`) in its own user namespace; without it the web helper dies at start (`FATAL:zygote_host_impl_linux.cc`) and Steam shows a blank window |

Everything else is RuntimeDefault: default action ERRNO (EPERM), the same
architectures, the `socket` and `personality` argument filters, and the same
allow list. The kernel still checks capabilities on the allowed syscalls, so a
process in the pod's user namespace can only mount, set a hostname or chroot
inside a namespace it created itself (`chroot` needs `CAP_SYS_CHROOT` in the
caller's user namespace, so it cannot leave the container's root). The profile
is therefore only meant for pods with `hostUsers: false`,
`capabilities.drop: [ALL]` and `allowPrivilegeEscalation: false`;
`procMount: Unmasked` is needed as well, or the kernel refuses a fresh procfs
mount under the runtime's masked `/proc` paths.

Not covered: RuntimeDefault adds syscall groups for capabilities a container
keeps (for example `CAP_SYS_PTRACE` or `CAP_NET_ADMIN`). This profile is static
and assumes none. If a workload keeps a capability, add that group explicitly
rather than switching it to Unconfined.

### Regenerating after a containerd change

The containerd version comes from the Talos release (`talosVersion` in
`../topf.yaml`). To rebuild the base and re-derive:

```go
// go run . > runtime-default.json   (go.mod requiring
// github.com/containerd/containerd/v2 at the deployed version)
package main

import (
    "encoding/json"
    "os"

    "github.com/containerd/containerd/v2/contrib/seccomp"
    specs "github.com/opencontainers/runtime-spec/specs-go"
)

func main() {
    sp := &specs.Spec{
        Process: &specs.Process{Capabilities: &specs.LinuxCapabilities{}},
        Linux:   &specs.Linux{},
    }
    enc := json.NewEncoder(os.Stdout)
    enc.SetIndent("", "  ")
    _ = enc.Encode(seccomp.DefaultProfile(sp))
}
```

Then drop the `clone` and `clone3` rules, add `chroot clone clone3 setns
unshare mount pivot_root sethostname umount2` to the unconditional allow list, write
the result to `runtime-default-userns.json`, and regenerate the YAML copy in
`../all/10-machine.yaml`. Both copies must stay equal; check with:

```sh
python3 -c '
import sys, json, yaml
docs = yaml.safe_load_all(open("kubernetes/clusters/fairy-k8s01/talos/all/10-machine.yaml"))
m = [d for d in docs if d and "machine" in d][0]
v = [p for p in m["machine"]["seccompProfiles"] if p["name"] == "runtime-default-userns.json"][0]["value"]
sys.exit(0 if v == json.load(open("kubernetes/clusters/fairy-k8s01/talos/seccomp/runtime-default-userns.json")) else 1)'
```
