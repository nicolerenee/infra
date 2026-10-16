---
description: How fairy-k8s01 and atlantis-k8s01 are joined with Cilium Cluster Mesh over the site-to-site tunnel, and what that changed in each cluster
---

# Cilium Cluster Mesh

fairy-k8s01 and atlantis-k8s01 are meshed with Cilium Cluster Mesh over the den1 site-to-site IPsec tunnel. Pods in one cluster can reach pods in the other by IP, and network policy can select peers by their cluster and pod labels instead of by CIDR.

## Identity

| Cluster | `cluster.name` | `cluster.id` | clustermesh-apiserver |
|---|---|---|---|
| atlantis-k8s01 | `atlantis-k8s01` | 1 | 10.140.250.250 (internal LoadBalancer pool) |
| fairy-k8s01 | `fairy-k8s01` | 2 | 10.189.250.250 (internal LoadBalancer pool) |

The cluster id is encoded in every security identity, so these values are not changed casually: changing one re-allocates all identities on that cluster.

## Datapath

Both clusters run native routing, not VXLAN. Each cluster's nodes share one L2 segment, so `autoDirectNodeRoutes` installs the intra-cluster pod routes, and each node advertises its pod CIDR over BGP: fairy to the UDM, atlantis to the den1 ToR. The native-routing CIDR on both clusters is `10.224.0.0/11`, which covers both pod ranges, so pod-to-pod traffic between the clusters keeps its pod source address; everything else leaving a pod is masqueraded to the node as before.

Native routing was chosen over VXLAN because fairy's pod overlay runs at the 9000-byte MTU of its uplinks while the IPsec path is 1400 bytes. Encapsulated traffic would have to fragment; routed traffic gets ICMP frag-needed and the tunnel's MSS clamp.

Native routing with IPv6 needs every node to have an on-link IPv6 address. Atlantis nodes have one from the site's public /64. Fairy nodes get a static ULA on the compute VLAN (`fd2b:ec92:e233::<ipv4 last octet>/64`) registered as the node's IPv6 InternalIP; the VLAN's delegated prefix is dynamic and is deliberately not used for this.

## Trust

Each cluster's clustermesh-apiserver and its agents' client certificates are issued by cert-manager from the `cilium-clustermesh-ca` ClusterIssuer. That CA is one key pair shared by both clusters, minted by tofu and delivered per cluster through GSM. Only the CA is shared; leaf certificates never leave their cluster.

## Exposure and firewalling

Pod addresses are routed addresses now. On fairy the UDM blocks every VLAN except the compute VLAN and the den1 VPN from both clusters' pod ranges, so clients keep using LoadBalancer IPs. Note the UDM classifies BGP-learned destinations as its External zone, which is where that policy lives. Den1 serves only infrastructure, so no equivalent is needed there.

## Checking

```bash
# on either cluster
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -E 'Cluster|ClusterMesh|Routing'
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg clustermesh status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg node list   # remote nodes appear with their cluster prefix
```

## Operational notes

- The Cilium chart reuses an existing `hubble-server-certs` Secret. After a cluster rename, delete that Secret before the upgrade or hubble-relay fails TLS and the Helm upgrade stalls.
- `clustermesh.config.enabled` must be true even with no peers listed, or the apiserver waits on a ConfigMap the chart does not render.
