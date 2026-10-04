---
description: Update DGX Spark firmware via fwupd in a privileged Kubernetes pod on Talos Linux
---

# Firmware Upgrades on DGX Spark (Talos Linux)

Talos Linux has no package manager and a read-only root filesystem, so fwupd cannot
run natively. Firmware updates are performed via a privileged Kubernetes pod that
installs fwupd at runtime, mounts the host's EFI System Partition, and stages UEFI
capsule updates for the next reboot.

## Quick Reference

```bash
# Deploy the fwupd pod on a specific node
task k8s:fwupd node=dgx01

# Exec into the pod
kubectl exec -n kube-system -it fwupd-dgx01 -- bash

# Check for available updates
fwupdtool get-updates

# Stage all updates (applied on next reboot)
fwupdtool update --no-reboot-check -y

# Confirm the capsule-delivery bit is set (byte 5 must be 04, not 00)
od -An -tx1 /sys/firmware/efi/efivars/OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Clean up
kubectl delete pod -n kube-system fwupd-dgx01
```

The pod startup also remounts efivarfs read-write and runs `fwupdtool refresh`; see
[Known Issues](#known-issues-and-gotchas) for why both are required on Talos.

The `task k8s:fwupd` command creates a privileged pod pinned to the specified node,
waits for it to be ready (fwupd is installed at startup), and prints the exec
command. The pod name is derived from the node name (e.g., `fwupd-dgx01`).

To update multiple nodes, clean up the pod and run the task again with a different
node name. The pod uses `restartPolicy: Never` so it won't reschedule on its own.

## Updatable Firmware Components

The DGX Spark has the following firmware components accessible via fwupd/LVFS:

| Component | LVFS ID | Update Method | Notes |
|-----------|---------|---------------|-------|
| Embedded Controller | `NVIDIA DGX Spark EC` | UEFI capsule | Board management controller |
| SoC Firmware | `NVIDIA DGX Spark SoC` | UEFI capsule | UEFI + GPU VBIOS combined |
| USB-C PD Controller | `NVIDIA DGX Spark USBC` | UEFI capsule | USB Type-C power delivery |
| NVMe (Samsung) | — | UEFI capsule | Rarely has updates on LVFS |
| UEFI dbx | — | UEFI capsule | Secure boot revocation list |
| ConnectX-7 NICs | — | **Not updatable via fwupd** | Use mlxfwmanager instead |

### Firmware Update History

Updated on dgx01, dgx02, dgx03 from Talos via the fwupd pod (2026-10-03). All three
components flashed in a single reboot even from the `0x02004xxx` EC line; no
intermediate EC step was needed. dgx04 through dgx07 shipped at this level.

| Component | dgx01 | dgx02 | dgx03 | After (all) | LVFS Release |
|-----------|-------|-------|-------|-------------|--------------|
| Embedded Controller | `0x02004e18` | `0x02004b03` | `0x02004e12` | `0x03000508` | 2026-06-05 |
| SoC Firmware (UEFI+GPU) | `0x0200941a` | `0x02009009` | `0x02009418` | `0x02009b0b` | 2026-06-12 |
| USB-C PD Controller | `0x00000507` | `0x00000001` | `0x00000500` | `0x00000516` | 2026-02-19 |

Updated on dgx01 from stock DGX OS (2026-04-13):

| Component | Before | After | LVFS Release |
|-----------|--------|-------|--------------|
| Embedded Controller | `0x02004b03` | `0x02004e18` | 2026-03-13 |
| SoC Firmware (UEFI+GPU) | `0x02009009` | `0x0200941a` | 2026-02-24 |
| USB-C PD Controller | `0x00000500` | `0x00000507` | 2025-12-04 |

## How It Works

### The Pod

The pod is created by `task k8s:fwupd` (defined in `.taskfiles/k8s/taskfile.yaml`).
On startup it:

1. Installs `fwupd` and `locales` packages from Ubuntu repos
2. Generates `en_US.UTF-8` locale (fwupd output has Unicode box-drawing characters)
3. Creates `/boot/efi` and mounts the ESP partition (`/dev/nvme0n1p1`)
4. Sleeps forever, waiting for you to exec in and run commands

The pod requires:

- **Privileged mode** — needed to access firmware interfaces and mount the ESP
- **hostPID** — fwupd needs visibility into host processes
- **hostNetwork** — fwupd downloads metadata and firmware from LVFS
- **Host volume mounts** — `/sys/firmware`, `/sys/bus`, `/sys/class`, `/sys/devices`,
  `/dev`, `/run/udev` for hardware enumeration
- **GPU toleration** — DGX nodes have a `nvidia.com/gpu` NoSchedule taint

### ESP Discovery

fwupd normally discovers the EFI System Partition via `/etc/fstab` or systemd mount
units, neither of which exist on Talos. The workaround:

- The `FWUPD_UEFI_ESP_PATH=/boot/efi` environment variable tells fwupd where the
  ESP is mounted
- The startup script mounts `/dev/nvme0n1p1` (the ESP) to `/boot/efi`

The startup script auto-detects the ESP by finding the first vfat partition via
`blkid`. On DGX Spark this is `/dev/nvme0n1p1`; on other nodes it may differ.

To verify the ESP was mounted correctly:

```bash
df -h /boot/efi
```

### UEFI Capsule Update Flow

1. `fwupdtool update --no-reboot-check` downloads firmware from LVFS and writes
   capsule files to the ESP (under `/boot/efi/EFI/UpdateCapsule/`)
2. It also sets EFI variables telling the UEFI firmware to process the capsules on
   next boot
3. On reboot, the UEFI firmware reads the capsules and flashes them **before** the
   OS boots
4. The reboot takes significantly longer than normal (several minutes) while firmware
   is being flashed — this is expected

## Useful Commands

All commands below are run from inside the fwupd pod (`kubectl exec -it`):

```bash
# List all detected hardware and current firmware versions
fwupdtool get-devices

# JSON output (useful for scripting — works for get-devices only)
fwupdtool get-devices --json

# Check for available updates
fwupdtool get-updates

# Stage all available updates (reboot to apply)
fwupdtool update --no-reboot-check

# Update a specific device only
fwupdtool update --no-reboot-check <DEVICE-ID>

# Verify capsules were staged to the ESP
ls -la /boot/efi/EFI/UpdateCapsule/

# Force metadata refresh from LVFS
fwupdtool refresh
```

## Known Issues and Gotchas

### Talos mounts efivarfs read-only, so staging silently does nothing

Talos mounts `/sys/firmware/efi/efivars` read-only. `fwupdtool update` still
downloads the capsules and writes them to the ESP, exits 0, and reports the device
as updated, but it cannot set bit 2 (`FILE_CAPSULE_DELIVERY`) in the `OsIndications`
EFI variable. UEFI then ignores the capsules on reboot and the versions come back
unchanged. The pod startup now runs `mount -o remount,rw /sys/firmware/efi/efivars`
(a superblock remount from the privileged container is enough). After staging,
`get-devices` must show `Update State: Needs reboot` and `OsIndications` must have
byte 5 set to `04`; if either is missing, nothing will flash.

### A fresh pod has no LVFS metadata

`get-updates` and `update` only know about releases after `fwupdtool refresh`.
Without it the DGX devices show as generic `UEFI Device Firmware` with no updates,
which looks like "already current". The pod startup now runs the refresh, but if
it was cut short (no egress yet, LVFS slow) run it again by hand.

### Stray capsules left on the ESP

Occasionally one capsule file stays in `/boot/efi/EFI/UpdateCapsule/` after a
successful flash (seen with the USB-C PD capsule on dgx01). Once `get-devices`
confirms the new version, delete the leftover so a later staging run starts clean.

### `fwupdtool get-updates --json` does not output JSON

This is a bug in the fwupd version shipped with Ubuntu 24.04. The `--json` flag
works correctly with `get-devices` but `get-updates` outputs plain text regardless.
Use `get-devices --json` instead — the `Releases` array in the JSON output includes
available update information.

### fwupd config file `EspLocation` does not work in this setup

Neither `[fwupd]` nor `[uefi_capsule]` config sections with `EspLocation` work
reliably in the container. The `FWUPD_UEFI_ESP_PATH` environment variable is the
only reliable method for ESP discovery.

### ConnectX-7 firmware is not updatable via fwupd

fwupd detects the ConnectX-7 NICs but shows firmware version `01` and has no updates
on LVFS. Use Mellanox's `mlxfwmanager` tool for CX7 firmware updates instead.

### Pod startup takes 30-60 seconds

The pod installs packages on every start since it uses a stock `ubuntu:24.04` image.
If you need to run this frequently, consider building a custom image with fwupd
pre-installed.

### Rebooting a Talos node after staging

After staging firmware updates, reboot the node with:

```bash
talosctl reboot -n <node-ip> --mode powercycle
```

Always use `--mode powercycle`; the Sparks hang on a kexec reboot. The firmware
flash happens during POST. Expect the node to be NotReady for roughly 10 minutes
when all three capsules are staged (the EC update power-cycles the board on its
own). If running workloads on the node, drain it first:

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
talosctl reboot -n <node-ip> --mode powercycle
# After it comes back:
kubectl uncordon <node-name>
```

### Verifying updates were applied

After reboot, redeploy the fwupd pod and check versions:

```bash
task k8s:fwupd node=dgx01
kubectl exec -n kube-system fwupd-dgx01 -- fwupdtool get-devices --json | jq '.Devices[] | {Name, Version}'
```
