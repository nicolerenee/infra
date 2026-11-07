#!/usr/bin/env bash
set -euo pipefail

# Inherit the runner or job hook settings so a missing injection fails visibly.
python - <<'PY'
import os
from urllib.parse import urlparse

base = "http://package-proxy.dev-platform.svc.cluster.local:8080"
expected = {
    "GOPROXY": base + "/go",
    "GOSUMDB": "sum.golang.org " + base + "/go/sumdb/sum.golang.org",
    "GOPRIVATE": "github.com/frecklelabs/*",
    "GONOPROXY": "github.com/frecklelabs/*",
    "NPM_CONFIG_REGISTRY": base + "/npm/",
    "PIP_INDEX_URL": base + "/pypi/simple/",
    "UV_INDEX_URL": base + "/pypi/simple/",
    "PIP_TRUSTED_HOST": urlparse(base).hostname,
    "UV_INSECURE_HOST": urlparse(base).netloc,
}
for key, value in expected.items():
    assert os.environ.get(key) == value, f"Unexpected or missing {key}"
assert not os.environ.get("PIP_EXTRA_INDEX_URL"), "Extra Python index bypasses the proxy"
print("Inherited Go, sumdb, npm, pip and uv settings match the package proxy")
PY

smoke_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/package-proxy-smoke.XXXXXX")
export GOMODCACHE="$smoke_dir/go-mod" GOCACHE="$smoke_dir/go-build"
export GOTOOLCHAIN=local PIP_CONFIG_FILE=/dev/null PIP_DISABLE_PIP_VERSION_CHECK=1
touch "$smoke_dir/npm-user-config" "$smoke_dir/npm-global-config"
export NPM_CONFIG_USERCONFIG="$smoke_dir/npm-user-config" NPM_CONFIG_GLOBALCONFIG="$smoke_dir/npm-global-config"
mkdir -p "$smoke_dir/go" "$smoke_dir/npm"

date -u '+Package smoke started: %Y-%m-%dT%H:%M:%SZ'
go version
node --version
python --version

cd "$smoke_dir/go"
cat > go.mod <<'EOF'
module example.com/package-proxy-smoke

go 1.27.0

require gopkg.in/yaml.v3 v3.0.1
EOF
cat > main.go <<'EOF'
package main

import "gopkg.in/yaml.v3"

func main() {
    var value map[string]string
    if err := yaml.Unmarshal([]byte("cache: works\n"), &value); err != nil {
        panic(err)
    }
    if value["cache"] != "works" {
        panic("unexpected YAML result")
    }
}
EOF
go mod tidy -x
go build -x -o smoke .
./smoke
# A fresh checksum database cache establishes that verification was performed.
test -s "$GOMODCACHE/cache/download/sumdb/sum.golang.org/lookup/gopkg.in/yaml.v3@v3.0.1"

cd "$smoke_dir/npm"
printf '%s\n' '{"name":"package-proxy-smoke","version":"1.0.0","private":true,"dependencies":{"is-number":"7.0.0"}}' > package.json
npm install --package-lock-only --ignore-scripts --no-audit --no-fund --cache "$smoke_dir/npm-lock-cache"
node <<'JS'
const assert = require('node:assert/strict');
const lock = require('./package-lock.json');
const resolved = lock.packages['node_modules/is-number'].resolved;
assert.ok(resolved.startsWith(process.env.NPM_CONFIG_REGISTRY), 'Lockfile bypasses proxy');
JS
npm ci --ignore-scripts --no-audit --no-fund --cache "$smoke_dir/npm-ci-cache"
node -e 'require("node:assert/strict").equal(require("is-number")(42), true)'

python -m venv "$smoke_dir/venv"
"$smoke_dir/venv/bin/python" -m pip install --no-cache-dir six==1.17.0
"$smoke_dir/venv/bin/python" -c 'import six; assert six.__version__ == "1.17.0"'
date -u '+Package smoke passed: %Y-%m-%dT%H:%M:%SZ'
