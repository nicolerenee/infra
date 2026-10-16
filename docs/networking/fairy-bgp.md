---
description: How fairy-k8s01 announces LoadBalancer IPs to the fairy UDM over BGP, and what the UDM accepts
---

# Fairy BGP (Cilium to UDM)

Every fairy-k8s01 node runs an eBGP session to the UDM and announces the cluster's LoadBalancer IPs as /32 routes plus its own pod /24. This is the only way the LoadBalancer pools are reachable on the home network, and with native routing it is how the UDM knows which node owns a pod address.

## Why

Fairy's LoadBalancer pools (`10.189.250.0/24` internal, and the public pool defined from the `site-public-ips` Secret) are not on any VLAN subnet, and nothing announces them at L2. Without a route on the UDM, traffic to those addresses leaves through the WAN. BGP gives the UDM a per-address route to the nodes that actually carry the Service, with ECMP across nodes.

## Topology

| Side | ASN | Address | Role |
|---|---|---|---|
| fairy-k8s01 nodes | 64613 | 10.189.3.16 to .28 (VLAN 1000) | Cilium BGP control plane, one session per node |
| fairy-udm01 | 64614 | 10.189.3.1 | Passive peer-group with a listen range over the VLAN |

ASN allocation across sites: 64610 border1-den1, 64611 den1 spines, 64612 atlantis-k8s01, 64613 fairy-k8s01, 64614 fairy-udm01.

## Cluster side

The manifests are in `kubernetes/clusters/fairy-k8s01/apps/kube-system/bgp/`, applied by their own Flux Kustomization that depends on `cilium`:

- `CiliumBGPClusterConfig` selects every Linux node and defines the single peer.
- `CiliumBGPPeerConfig` sets eBGP TTL 1, 10/30 second timers and graceful restart.
- `CiliumBGPAdvertisement` announces `LoadBalancerIP` for every `LoadBalancer` Service, and each node's `PodCIDR`. Label a Service `bgp.freckle.systems/advertise: "false"` to opt it out.

Services with `externalTrafficPolicy: Local` are announced only from nodes with a ready endpoint.

## Pod networks are routed, so they are firewalled

Cilium runs in native routing mode on fairy (no VXLAN), so pod addresses are plain routed addresses once the UDM has the per-node routes. The UDM firewall blocks every VLAN except Infra - Compute & Storage and the den1 site-to-site VPN from reaching the pod ranges of both clusters; clients use LoadBalancer IPs. That policy is managed as code in the private network repo.

## UDM side

The FRR-format file lives in the private network repo and is uploaded through the UniFi UI (Settings, Routing, BGP). It accepts only prefixes inside the two LoadBalancer pools and the pod /24s, and announces nothing back to the nodes.

## Checking

```bash
# Cluster: session state on one node
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bgp peers

# Cluster: what a node advertises
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bgp routes advertised ipv4 unicast

# UDM (SSH): neighbors and learned routes
vtysh -c 'show ip bgp summary'
vtysh -c 'show ip route bgp'
```
