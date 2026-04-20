---
description: Glossary of acronyms and terms used throughout the infrastructure documentation
---

# Glossary

## Networking

| Term | Definition |
|------|------------|
| ASW | Access switch — provides endpoint connectivity for a network segment |
| BGP | Border Gateway Protocol — routing protocol used by Cilium to announce Kubernetes service IPs |
| FSW | Fabric switch — high-speed east-west switch for GPU-to-GPU traffic |
| GW | Gateway — site router/firewall that handles inter-VLAN routing and internet access |
| GPON | Gigabit Passive Optical Network — fiber access technology used by AT&T |
| LLDP | Link Layer Discovery Protocol — neighbor discovery on Ethernet |
| MDF | Main distribution frame — central wiring point where outside lines enter and internal cabling originates |
| MSW | Management switch — dedicated out-of-band network for IPMI, BMC, and infrastructure management |
| RDMA | Remote Direct Memory Access — low-latency data transfer bypassing the CPU |
| ToR | Top-of-rack switch — primary data switch in a server rack |
| VLAN | Virtual LAN — logical network segmentation on a shared switch |
| VSW | PoE / video switch — switch dedicated to powering and connecting cameras or outdoor endpoints |

## Compute

| Term | Definition |
|------|------------|
| BMC | Baseboard Management Controller — out-of-band management processor on a server motherboard |
| C2C | Chip-to-Chip — NVIDIA's direct interconnect between Grace CPU and Blackwell GPU on the DGX Spark |
| DGX Spark | NVIDIA's compact ARM64 AI workstation with a GB10 (Grace Blackwell) SoC |
| Freckle | Custom-built rackmount compute nodes designed for this homelab |
| GSP | GPU System Processor — NVIDIA firmware that runs on the GPU for driver offloading |
| IPMI | Intelligent Platform Management Interface — standard for out-of-band server management |
| JetKVM | Compact IP KVM device for remote keyboard/video/mouse access |
| MCIO | Mini Cool Edge IO — high-density PCIe connector used to break out NVMe lanes from the motherboard |
| vPro | Intel Active Management Technology — remote management built into Intel CPUs |

## Storage

| Term | Definition |
|------|------------|
| Ceph | Distributed storage system providing block (RBD), filesystem (CephFS), and object storage |
| CephFS | Ceph's POSIX filesystem layer |
| CSI | Container Storage Interface — Kubernetes standard for storage drivers |
| OSD | Object Storage Daemon — a Ceph process managing a single storage device |
| RBD | RADOS Block Device — Ceph's block storage interface, used for Kubernetes PVCs |
| raidz2 | ZFS RAID level with double parity — tolerates two drive failures per vdev |

## Kubernetes & GitOps

| Term | Definition |
|------|------------|
| Cilium | eBPF-based CNI plugin for Kubernetes networking and security |
| Flux | GitOps toolkit that keeps Kubernetes clusters in sync with Git repositories |
| HelmRelease | Flux CRD that declares a Helm chart deployment and its values |
| Kustomization | Flux CRD that applies a set of Kubernetes manifests from a Git path |
| PVC | Persistent Volume Claim — a Kubernetes request for storage |
| Talos Linux | Immutable, API-driven Linux distribution purpose-built for Kubernetes |
| vLLM | High-throughput LLM inference engine used on the DGX Spark nodes |

## Power

| Term | Definition |
|------|------------|
| PDU | Power Distribution Unit — distributes mains power to rack equipment |
| UPS | Uninterruptible Power Supply — battery backup for clean shutdowns during power loss |

## Firewalla

Firewalla uses some non-standard terminology in its UI and documentation.

| Term | Definition |
|------|------------|
| VqLAN | Firewalla's name for a VLAN-tagged network segment configured through its UI — functionally a standard 802.1Q VLAN |
| Network Segment | Firewalla's term for an isolated L2/L3 network, which may be a VLAN, a bridge, or a VPN-backed segment |
| `post_main.d` | Hook directory (`/home/pi/.firewalla/config/post_main.d/`) for scripts that run after Firewalla's main services start — survives firmware updates |

## Appliances

| Term | Definition |
|------|------------|
| UNVR | UniFi Network Video Recorder — Ubiquiti's dedicated NVR appliance for UniFi Protect |
