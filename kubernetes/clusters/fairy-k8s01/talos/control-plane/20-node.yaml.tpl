---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  networks.freckle.systems/home-lan: present
  topology.freckle.systems/rack: r01
  # Which PDU (and therefore UPS) feeds this node: topf.yaml data.powerFeed,
  # pdu01 (ups01, odd-numbered devices) or pdu02 (ups02, even). Multi-node
  # inference pods use it as a topologyKey so a tensor-parallel pair sits on
  # one feed and a single UPS event can't take out half a model.
  topology.freckle.systems/power-feed: {{ .Node.Data.powerFeed }}
