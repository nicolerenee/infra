---
# 10GbE cluster link to r01-tor01. Jumbo like the cn bonds; Cilium derives
# its MTU from this link, so 1500 here left the cluster mixed.
# dgx01-03 are statically addressed; newer sparks (topf.yaml `data.dhcp`)
# take a UDM DHCP reservation instead.
apiVersion: v1alpha1
kind: LinkConfig
name: enP7s7
mtu: 9000
addresses:
  # Static on-link IPv6 (host part = the IPv4 last octet), on every node even
  # when IPv4 comes from DHCP: Cilium's native-routing direct routes need a
  # reachable IPv6 node address (see all/10-machine nodeIP.validSubnets).
  - address: fd2b:ec92:e233::{{ .Node.IP.String | splitList "." | last }}/64
{{- if not (hasKey .Node.Data "dhcp") }}
  - address: {{ .Node.IP }}/24
routes:
  - gateway: 10.189.3.1
    metric: 1024
{{- end }}
{{- if hasKey .Node.Data "dhcp" }}
---
apiVersion: v1alpha1
kind: DHCPv4Config
name: enP7s7
{{- end }}
---
# ConnectX-7 fabric ports (NCCL only, no host addressing).
apiVersion: v1alpha1
kind: LinkConfig
name: enp1s0f0np0
mtu: 9000
---
apiVersion: v1alpha1
kind: LinkConfig
name: enP2p1s0f0np0
mtu: 9000
---
apiVersion: v1alpha1
kind: LinkConfig
name: enp1s0f1np1
mtu: 9000
---
apiVersion: v1alpha1
kind: LinkConfig
name: enP2p1s0f1np1
mtu: 9000
