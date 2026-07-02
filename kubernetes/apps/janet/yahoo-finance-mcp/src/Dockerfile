# Yahoo Finance MCP (vendored Alex2Yang97/yahoo-finance-mcp, streamable-HTTP
# entrypoint — see http_entrypoint.py). python:3.11-slim + uv, mirroring the
# upstream project's own Dockerfile shape (uv-image install stage -> slim
# runtime, `uv pip install --system`), but non-root here since we own this
# build (unlike brave-search-mcp / google-workspace-mcp, whose upstream image
# user is unconfirmed — see their TODO(hardening) comments).
#
# Build (Nicole runs this manually — not run by CI in this PR):
#   docker build -t ghcr.io/nicolerenee/yahoo-finance-mcp:0.1.0 \
#     kubernetes/apps/janet/yahoo-finance-mcp/src
#   docker push ghcr.io/nicolerenee/yahoo-finance-mcp:0.1.0

FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS uv

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY pyproject.toml .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system -r pyproject.toml

# --- runtime -----------------------------------------------------------------
FROM python:3.11-slim

RUN groupadd --system --gid 65532 mcp && \
    useradd --system --uid 65532 --gid mcp --no-create-home --shell /usr/sbin/nologin mcp

WORKDIR /app

# Bring over the interpreter's site-packages + installed console scripts from
# the uv stage (same layout upstream's own Dockerfile copies).
COPY --from=uv /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=uv /usr/local/bin /usr/local/bin
COPY server.py http_entrypoint.py ./

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    YFINANCE_MCP_HOST=0.0.0.0 \
    YFINANCE_MCP_PORT=8000

USER mcp
EXPOSE 8000

ENTRYPOINT ["python", "http_entrypoint.py"]
