---
# 10G uplink: single-member active-backup bond so a second port can be
# added without re-addressing. Jumbo end to end (r01-tor01 passes 9000).
apiVersion: v1alpha1
kind: BondConfig
name: bond0
links:
  - eno3
bondMode: active-backup
mtu: 9000
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: 10.189.3.1
    metric: 1024
---
# Home-LAN VLAN sub-interface. No address: it is purely the bridge port for
# br-homelan. The VLAN ID lives here and in Cilium's `bpf.vlanBypass`
# (clusters/fairy-k8s01/apps/kube-system/cilium.yaml) -- nothing else in the
# cluster refers to the number, everything attaches to the bridge by name.
apiVersion: v1alpha1
kind: VLANConfig
name: bond0.500
vlanID: 500
parent: bond0
mtu: 1500
---
# L2 bridge over the home LAN. Parent for KubeVirt VM bridge-CNI attachments
# and macvlan pod attachments (multus-trusted, multus-vm-trusted). Named by
# purpose, not VLAN, so a VLAN renumber never touches the k8s side. The
# bridge holds no IP; STP disabled (single port = no loops).
#
# The MAC is pinned per node (topf.yaml `data.homelanBridgeMac`): locally-
# administered 02:1f:80:03:00:NN, NN = cn-node number (the 03:00 is historical,
# from when this was VLAN 300; left alone since nothing depends on it).
# Without pinning the kernel synthesizes a random MAC each boot (observed
# 16:f4:… → 0e:da:… across a single reboot).
apiVersion: v1alpha1
kind: BridgeConfig
name: br-homelan
hardwareAddr: {{ .Node.Data.homelanBridgeMac | quote }}
links:
  - bond0.500
stp:
  enabled: false
mtu: 1500
