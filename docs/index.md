# Infra Docs

This is the documentation for a personal homelab infrastructure built around
Kubernetes on bare metal. The clusters run [Talos Linux](https://www.talos.dev/)
on custom-built compute nodes and [NVIDIA DGX Spark](https://www.nvidia.com/en-us/autonomous-machines/dgx-spark/)
GPU nodes, with [Flux](https://fluxcd.io/) for GitOps delivery and
[Ceph](https://ceph.io/) for distributed storage. Everything is declared in a
single Git repository — Kubernetes manifests, Talos machine configs, and the
docs you're reading now.

!!! warning "Work in progress"

    These docs are still being built out and are largely incomplete.

## Sites

- [Fairy](sites/fairy/index.md) — primary homelab site with compute rack,
  GPU nodes, and home network infrastructure

## Runbooks

- [Firmware Upgrades](runbooks/firmware-upgrades.md) — DGX Spark firmware
  updates via fwupd on Talos Linux

## Guides

- [AT&T 802.1X Bypass](guides/att-802.1x-bypass.md) — wpa_supplicant on
  Firewalla Gold Pro

## Reference

- [Naming Conventions](naming-conventions.md) — device and cluster naming
  scheme
- [Glossary](glossary.md) — acronyms and terms used in these docs
