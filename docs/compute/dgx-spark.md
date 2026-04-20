---
description: NVIDIA DGX Spark (GB10) configuration on Talos Linux — driver selection, GPU operator, and network interfaces
---

# DGX Spark (GB10)

The fairy site runs three NVIDIA DGX Spark nodes (fairy-r02-dgx01 through fairy-r02-dgx03)
as GPU worker nodes in the fairy-k8s01 Kubernetes cluster, providing inference
and model loading capabilities.

## Hardware

- **SoC**: NVIDIA GB10 (Grace CPU + Blackwell GPU via C2C interconnect)
- **CPU**: Grace, 12-core ARM64
- **GPU**: Blackwell, 128 TFlops
- **Memory**: 128GB unified (shared CPU+GPU)
- **Storage**: 4TB NVMe
- **NICs**: 2x Mellanox ConnectX-7 QSFP56 (exposed as 4 interfaces via PCIe lane splitting), 1x Realtek RTL8127 10G copper

## Driver Selection

GB10 devices require the proprietary NVIDIA driver on Talos — open-source
drivers are [not supported](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/hardware-and-drivers/nvidia-gpu).

| Driver | Package | Version | Status |
|--------|---------|---------|--------|
| Proprietary production | `nonfree-kmod-nvidia-production` | 595.58.03 | **In use** — works correctly |
| Open production | `nvidia-open-gpu-kernel-modules-production` | 595.x | CUDA broken (`cuInit()` error 3) |
| Open LTS | `nvidia-open-gpu-kernel-modules-lts` | 580.126.20 | Untested on Talos (stock DGX OS ships 580.126.09) |

As of Talos v1.13.0-beta.1 (tested April 2026), the open-source production
driver causes CUDA initialization failures (`cuInit()` error 3) in containers.
This may be resolved in future Talos or driver releases.

See the Talos [proprietary GPU driver docs](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/hardware-and-drivers/nvidia-gpu-proprietary)
for setup instructions.

## Talos Extensions

| Extension | Purpose |
|-----------|---------|
| `siderolabs/nonfree-kmod-nvidia-production` | Proprietary NVIDIA kernel module |
| `siderolabs/nvidia-container-toolkit-production` | NVIDIA container runtime |
| `siderolabs/iscsi-tools` | iSCSI client |
| `siderolabs/lldpd` | LLDP discovery |

## GPU Operator

GPU Operator v26.3.0 cannot parse Talos version strings (e.g., `v1.13.0-beta.1`).

**Workaround**: Use patched operator image `ghcr.io/nvidia/gpu-operator:670be908`

See [GPU Operator issue #2239](https://github.com/NVIDIA/gpu-operator/issues/2239).

## Kernel Parameters

- `arm64.nobti` — required on GB10 devices or the system may crash and CUDA
  libraries will not load. See the
  [Talos proprietary GPU docs](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/hardware-and-drivers/nvidia-gpu-proprietary)
  and [talos#13019](https://github.com/siderolabs/talos/issues/13019#issuecomment-4229926476).

Parameters from the stock DGX OS investigation (not currently applied on Talos,
documented for reference):

- `nvidia_drm modeset=0`
- `init_on_alloc=0`
- `pci=pcie_bus_safe`

## Node Taints

All DGX nodes are tainted with `nvidia.com/gpu=NoSchedule` so only workloads
that explicitly tolerate GPU scheduling land on them. Typical workloads include
vLLM inference and model loading.

## Network Interfaces

Each DGX Spark has 2 physical ConnectX-7 QSFP56 ports and 1 Realtek RTL8127
10G copper port. Each physical CX-7 port is split across two PCIe lanes,
presenting as two OS interfaces per physical port.

### Physical Port 0 — GPU fabric via fairy-r02-fsw01

Connected via a 400G to 2x200G DAC breakout cable to the GPU fabric switch
(MikroTik CRS804-4DDQ, fairy-r02-fsw01) for inter-node GPU communication
(GPUDirect RDMA, tensor/pipeline parallelism).

| Interface | MTU |
|-----------|-----|
| enp1s0f0np0 | 9000 |
| enP2p1s0f0np0 | 9000 |

### Physical Port 1 — Not connected

| Interface | MTU |
|-----------|-----|
| enp1s0f1np1 | 9000 |
| enP2p1s0f1np1 | 9000 |

### Realtek RTL8127 — Primary network

| Interface | Speed | MTU |
|-----------|-------|-----|
| enP7s7 | 10G | 1500 |

Handles all Kubernetes and management traffic via fairy-r02-tor01 (Netgear
XS724EMv2).
