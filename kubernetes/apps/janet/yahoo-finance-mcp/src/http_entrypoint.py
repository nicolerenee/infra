"""Streamable-HTTP entrypoint for the vendored Yahoo Finance MCP server.

server.py (vendored verbatim from upstream) only exposes stdio transport via
its own main(); janet-brain's MCP client talks streamable-HTTP (see the
sibling brave-search-mcp / google-workspace-mcp servers in this repo — same
transport, no stdio<->HTTP shim, retired in janet-brain PR #32). Rather than
patching the vendored file, this module imports the already-constructed
`yfinance_server` FastMCP instance and drives it over HTTP, so re-vendoring
server.py from upstream stays a clean drop-in (no merge conflicts with our
patches).

Two things must happen before calling `.run(transport="streamable-http")`:

1. Bind host/port. FastMCP's `Settings` default to 127.0.0.1:8000 and are
   fixed at `FastMCP(...)` construction time inside server.py, so they're
   mutated here post-construction via `.settings.host` / `.settings.port`
   (both are read lazily by `run_streamable_http_async()`, not baked into a
   request handler at construction time — safe to mutate right up until
   `.run()` is called).

2. Disable DNS-rebinding host-header validation. FastMCP auto-enables it
   when constructed with the default host "127.0.0.1" (locking `Host:` to
   127.0.0.1/localhost/::1 literals), which would reject every request that
   arrives via the Kubernetes Service DNS name
   (yahoo-finance-mcp.janet-mcp.svc.cluster.local). That protection guards
   against browser-based DNS-rebinding attacks against a server bound to
   localhost; it has no purpose for a ClusterIP-only backend with no public
   ingress, so it's turned off here rather than trying to enumerate every
   Host header a cluster client might send.
"""

import os

from mcp.server.transport_security import TransportSecuritySettings
from server import yfinance_server


def main() -> None:
    host = os.environ.get("YFINANCE_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("YFINANCE_MCP_PORT", "8000"))

    yfinance_server.settings.host = host
    yfinance_server.settings.port = port
    yfinance_server.settings.transport_security = TransportSecuritySettings(
        enable_dns_rebinding_protection=False
    )

    print(f"Starting Yahoo Finance MCP server on {host}:{port} (streamable-http, path=/mcp)")
    yfinance_server.run(transport="streamable-http")


if __name__ == "__main__":
    main()
