# Home Kubernetes Infrastructure

A GitOps-managed Kubernetes infrastructure running on bare metal with Talos
Linux, featuring automated deployments via Flux v2 and comprehensive
application hosting for home lab services.

## 🏗️ Infrastructure Overview

This repository manages two Kubernetes clusters using a GitOps approach:

- **atlantis-k8s01**: 5-node cluster (3 control plane, 2 workers) with
  high-availability networking running in a Colo
- **fairy-k8s01**: 3-node cluster (all control plane) running at home

### Core Technologies

- **OS**: [Talos Linux](https://www.talos.dev/) - Immutable, secure Kubernetes
  OS
- **GitOps**: [Flux v2](https://fluxcd.io/) - Automated deployment and
  reconciliation
- **CNI**: [Cilium](https://cilium.io/) - eBPF-based networking with Gateway API
  support
- **Storage**: [Rook Ceph](https://rook.io/) - Distributed storage cluster
- **Secrets**: [External Secrets Operator](https://external-secrets.io/) with
  1Password integration
- **Monitoring**: [VictoriaMetrics](https://victoriametrics.com/) stack with
  Grafana
- **Load Balancing**: [MetalLB](https://metallb.universe.tf/) in BGP mode

## 📁 Repository Structure

```text
kubernetes/
├── apps/                   # Application definitions (shared across clusters)
│   ├── auth/               # Authentication services (Authentik, LLDAP)
│   ├── cert-manager/       # Certificate management
│   ├── flux/               # Flux operator and instance configs
│   ├── home-automation/    # Home Assistant, ESPHome, Zigbee2MQTT
│   ├── media/              # Media stack
│   ├── networking/         # Network services (Cilium, MetalLB, DNS)
│   ├── observability/      # Monitoring and alerting stack
│   ├── secrets/            # Secret management
│   ├── storage/            # Storage solutions
│   └── ...
├── clusters/               # Cluster-specific configurations
│   ├── atlantis-k8s01/     # atlantis cluster configuration
│   │   ├── apps/           # Cluster-specific app deployments
│   │   ├── flux/           # Flux bootstrap configuration
│   │   └── talos/          # Talos machine configurations
│   └── fairy-k8s01/        # fairy cluster configuration
└── components/             # Reusable Kustomize components
```

## 🚀 Key Features

### GitOps Automation

- **Flux v2** continuously monitors this repository and applies changes
  automatically
- **Renovate** keeps dependencies updated with automated PRs
- **GitHub Actions** provide CI/CD pipeline for validation and deployment

### Security & Secrets Management

- **1Password Connect** integration for secure secret management
- **External Secrets Operator** syncs secrets from 1Password to Kubernetes
- **Cert-Manager** with Let's Encrypt for automatic TLS certificate
  provisioning
- **Authentik** provides SSO and identity management

### High Availability Storage

- **Rook Ceph** cluster provides distributed, replicated storage
- **Spegel** for distributed container image caching

### Comprehensive Monitoring

- **VictoriaMetrics** for metrics collection and storage
- **Victoria Logs** for log aggregation and analysis
- **Grafana** for visualization and dashboards
- **Gatus** for uptime monitoring and status pages
- **Silence Operator** for intelligent alert management
- **Prometheus Operator** for metrics collection and alerting

### Networking & Connectivity

- **Cilium** with eBPF for high-performance networking
- **Gateway API** for modern ingress management
- **MetalLB** in BGP mode for LoadBalancer services
- **Tailscale** integration for secure remote access
- **Multus** for multi-network interface support
- **Cloudflare Tunnel** for secure external connectivity

## 🏠 Applications & Services

### Media & Entertainment

- **Emby/Jellyfin**: Media streaming servers
- **Plex**: Media streaming server
- **Sonarr/Radarr/Lidarr**: Media acquisition and management
- **Bazarr**: Subtitle management
- **SABnzbd**: Usenet downloader
- **Prowlarr**: Indexer management
- **Recyclarr**: Quality profile management
- **Webhook**: Automation webhook handler

### Home Automation

- **Home Assistant**: Home automation platform
- **ESPHome**: ESP device management
- **Zigbee2MQTT**: Zigbee device integration
- **Scrypted**: Camera and NVR management
- **Mosquitto**: MQTT message broker
- **rtl_433**: 433MHz radio receiver for IoT devices

### Development & Productivity

- **GitHub Actions Runners**: Self-hosted CI/CD runners
- **IT Tools**: Collection of useful web tools
- **Golink**: Internal URL shortener
- **Netbox**: Infrastructure documentation
- **Homebox**: Home inventory management
- **Mealie**: Recipe and meal planning management

### Infrastructure Services

- **Authentik**: Identity provider and SSO
- **LLDAP**: Lightweight LDAP server
- **Pocket ID**: Identity management platform
- **External DNS**: Automatic DNS record management
- **Cloudflare Tunnel**: Secure tunnel for external access
- **System Upgrade Controller**: Automated node updates (Kubernetes and Talos)
- **CloudNativePG**: PostgreSQL operator for database management

## 🔧 Hardware & Infrastructure

### Atlantis Cluster

- **5 nodes** with Intel hardware and 10Gb networking
- **Bonded network interfaces** with LACP for redundancy
- **NVMe boot storage** for quick boot speed
- **SSD ceph storage** for high-availablity cluster storage
- **Intel integrated graphics** support for hardware transcoding

### Fairy Cluster

- **3 nodes** (all control plane) with advanced security features
- **Secure Boot** and **UKI** enabled for enhanced security
- **NVMe storage** for boot device and ceph storage
- **Intel integrated graphics** support for media workloads

## 🚦 Getting Started

### Prerequisites

- **Talos Linux** knowledge for cluster management
- **Flux CLI** for GitOps operations
- **1Password** account for secrets management
- **Task** for automation scripts

### Bootstrap Process

1. **Prepare hardware** with Talos Linux installation
2. **Configure Talos** using the provided `talconfig.yaml` files
3. **Bootstrap Flux** using the cluster-specific configurations
4. **Set up secrets** in 1Password and configure External Secrets
5. **Deploy applications** by committing changes to this repository

### Task Automation

This repository uses [Task](https://taskfile.dev/) for automation:

```bash
# Generate Talos configurations
task talos:generate CLUSTER=atlantis-k8s01

# Apply Talos configuration to a node
task talos:apply-config CLUSTER=atlantis-k8s01 node=atlantis-compute01

# Update Talos configuration
task talos:talosconfig CLUSTER=atlantis-k8s01
```

## 🔄 Continuous Deployment

### Automated Updates

- **Renovate** automatically creates PRs for dependency updates
- **Flux** applies approved changes within minutes
- **System Upgrade Controller** handles node OS updates
- **Reloader** restarts applications when configurations change

### Monitoring & Alerting

- **VictoriaMetrics** collects metrics from all cluster components
- **Victoria Logs** aggregates and analyzes logs from all services
- **Grafana** provides comprehensive dashboards
- **Gatus** monitors service availability
- **Alert routing** via various notification channels

## 🤝 Contributing

This repository is tailored for personal use but serves as a reference
implementation. Feel free to:

- **Fork** and adapt for your own infrastructure
- **Open issues** for questions or suggestions
- **Submit PRs** for improvements or bug fixes

## 📚 Documentation & Resources

- [Talos Linux Documentation](https://www.talos.dev/docs/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Rook Ceph Documentation](https://rook.io/docs/)

## ⚠️ Important Notes

- **Secrets**: All secrets are managed via 1Password and External Secrets Operator
- **Networking**: BGP configuration required for MetalLB LoadBalancer services
- **Storage**: Rook Ceph requires dedicated storage devices on cluster nodes
- **Updates**: Automated updates are enabled - monitor the deployment pipeline

---

*This infrastructure powers a comprehensive home lab environment with
production-grade reliability and security.*
