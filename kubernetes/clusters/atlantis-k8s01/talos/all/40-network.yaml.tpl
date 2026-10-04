---
# 2x25G ConnectX ports in an LACP bond to the den1 spines; the bond carries
# the node's static v4 + v6 and both default routes (v6 gateway is the
# spines' shared link-local address).
apiVersion: v1alpha1
kind: LinkConfig
name: {{ .Node.Data.nic }}
mtu: 1500
---
apiVersion: v1alpha1
kind: LinkConfig
name: {{ .Node.Data.nic }}d1
mtu: 1500
---
apiVersion: v1alpha1
kind: BondConfig
name: bond0
links:
  - {{ .Node.Data.nic }}
  - {{ .Node.Data.nic }}d1
bondMode: 802.3ad
xmitHashPolicy: layer3+4
lacpRate: fast
miimon: 100
updelay: 200
downdelay: 200
mtu: 1500
addresses:
  - address: {{ .Node.IP }}/24
  - address: {{ .Node.Data.ip6 }}/64
routes:
  - gateway: 172.26.3.1
    metric: 1024
  - gateway: fe80::def
    metric: 1024
