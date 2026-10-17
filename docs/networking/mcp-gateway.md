---
description: One Envoy AI Gateway endpoint fronts every MCP server in both clusters, with freckle.id login for humans and ServiceAccount tokens for agents, and per-caller tool authorization
---

# MCP gateway

Every Model Context Protocol server in both clusters sits behind one gateway on
fairy. Humans log in with freckle.id, agents present their own ServiceAccount
token, and the gateway decides per caller which servers and tools they may use.
No MCP server has a route or a network path of its own.

## Why a gateway

The MCP servers (VictoriaMetrics, VictoriaLogs, VictoriaTraces and the Flux
Operator server, one of each per cluster) started life on the tailnet gateway
with no authentication, and the kagent agents reached them directly over
cluster DNS. Moving them to the internal gateway would have needed a login
per server and still said nothing about *which agent* may call *which tool*.
Envoy AI Gateway's `MCPRoute` does both: it aggregates many servers behind one
endpoint and carries ordered authorization rules keyed on the caller's token.

## Layout

```text
Claude Code ──freckle.id token──▶ mcp.fairy.freckle.services/mcp ──┐
                                                                   │  Gateway `mcp`
kagent agent ──SA token──▶ mcp-agents.fairy.freckle.services/mcp ──┤  10.189.250.21
                                                                   │
                        ┌──────────────────────────────────────────┘
                        ▼
   vlogs-fairy  vmetrics-fairy  vtraces-fairy  flux-fairy        (cluster DNS)
   vlogs-atlantis vmetrics-atlantis vtraces-atlantis flux-atlantis (Cluster Mesh global services)
```

- **Gateway `mcp`** (`gateway-system`, class `envoy`): its own address from the
  internal LoadBalancer pool, announced by BGP with `externalTrafficPolicy:
  Local`, its own `EnvoyProxy` so the AI extension's processor never sits in
  front of the household apps on the `internal` gateway. The access log records
  MCP method, backend and tool per request (never arguments or results).
- **Backends** are Envoy Gateway `Backend` objects named by service FQDN,
  because `MCPRoute` cannot reference Services in other namespaces. The
  atlantis entries resolve locally to Cluster Mesh global services.
- **Tool names** are prefixed by backend: `vmetrics-fairy__query`,
  `flux-atlantis__get_flux_instance`.

Manifests: `kubernetes/apps/networking/mcp-gateway/`, pointer
`kubernetes/clusters/fairy-k8s01/apps/gateway-system/mcp-gateway.yaml`.

## Humans: `mcp.fairy.freckle.services`

OAuth against freckle.id. The gateway publishes protected-resource metadata, so
an MCP client discovers the authorization server itself. Claude Code
identifies itself with a Client ID Metadata Document, so nothing is
pre-registered in pocket-id; the pocket-id side is a CIMD allow-list entry for
Claude Code's metadata URL and an API resource for the gateway with one
permission, `mcp:tools`, open to metadata-document clients. The route checks
the token's audience and then a CEL rule: the `mcp:tools` scope plus an
allow-list of user ids (`MCP_HUMAN_SUBJECTS` in the pointer). Humans get every
tool, including the Flux write tools.

```bash
claude mcp add --transport http freckle-services https://mcp.fairy.freckle.services/mcp
```

## Agents: `mcp-agents.fairy.freckle.services`

Same backends, different issuer: the cluster's own ServiceAccount token issuer,
already published at `k8s-oidc.freckle.systems` for workload identity. There
are no shared secrets; the gateway verifies the token against the cluster's
signing key, checks the audience, and authorizes on the subject:

| Agent | May call tools on |
|---|---|
| `cluster-triage` | `vmetrics-fairy`, `flux-fairy` |
| `cluster-triage-atlantis` | `vmetrics-atlantis`, `flux-atlantis` |
| `log-search` | `vlogs-fairy` |
| `log-search-atlantis` | `vlogs-atlantis` |

The Flux backends on this route are filtered to their read-only tools
(`get_*`, `trace_*`, `search_*`, `read_*`, `diff_*`) regardless of what the
server itself allows. The gateway also trims `tools/list` to what the rules
permit, so an agent only ever sees its own tools.

Tokens: a `kubernetes.io/service-account-token` Secret carries the legacy
issuer string `kubernetes/serviceaccount`, which the route cannot accept
(its `issuer` must be a URL), so the tokens come from the TokenRequest API. A
CronJob (`mcp-gateway-token-minter`, every 6 h) mints a 48 h token per agent
bound to the gateway's audience into `<agent>-gateway-token`; an
ExternalSecret through a kubernetes-provider SecretStore templates
`Authorization: Bearer <token>` (kagent sends header values verbatim); and the
agent's `RemoteMCPServer` references that. kagent watches the Secret and
rolls the agent on rotation. Manifests:
`kubernetes/apps/ai/agents/mcp-gateway-access/`.

## Network policy

- Each MCP server's ingress policy admits only the gateway's Envoy pods,
  named by fairy's cluster label so the same shared manifest works on atlantis
  where the Envoy is a Cluster Mesh peer.
- The `ai-agents` egress policy allows the gateway's Envoys on 10443 and no
  MCP server directly.
- The Flux Operator MCP server runs with its write tools enabled and
  cluster-admin RBAC; the gateway's two routes are its entire exposure.

## Operating notes

- Who called what: the `mcp` Envoy access log (`mcp_method`, `mcp_backend`,
  `mcp_tool`).
- A backend returning 503 during `tools/list` leaves that server's tools out of
  the client's session until it reconnects; check the backend pod first (the
  VictoriaMetrics server idles at ~480 MiB and needs its 1 GiB limit).
- Adding an agent: a rule on the agents route, an entry in the minter's
  `AGENTS` list and its Role `resourceNames`, and a block in
  `mcp-gateway-access/agents.yaml`.
- Adding a human: a user id in `MCP_HUMAN_SUBJECTS`.
