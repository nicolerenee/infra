"""Trusted-base entrypoint; untrusted repository objects are never executed."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

CONTEXT = "Public leak backstop"
REPO = "frecklelabs/k8s"


def main():
    head = None
    token = os.environ["GITHUB_TOKEN"]

    def api(path, data=None):
        request = urllib.request.Request(
            "https://api.github.com/repos/" + REPO + path,
            data=None if data is None else json.dumps(data).encode(),
            headers={"Authorization": "Bearer " + token,
                     "Accept": "application/vnd.github+json",
                     "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def status(state):
        api("/statuses/" + head, {"state": state, "context": CONTEXT,
            "description": "Trusted public content scan: " + state})

    def snapshot(pr):
        return (pr["head"]["sha"], pr["base"]["sha"], pr["title"], pr["body"])

    try:
        if os.environ["GITHUB_REPOSITORY"] != REPO:
            raise ValueError()
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        number = event["number"]
        if type(number) is not int or number <= 0:
            raise ValueError()
        pr = api("/pulls/" + str(number))
        head, base, title, body = snapshot(pr)
        if not all(re.fullmatch(r"[0-9a-f]{40}", sha) for sha in (head, base)):
            head = None
            raise ValueError()
        status("pending")
        subprocess.run(["go", "build", "-o", str(Path(os.environ["RUNNER_TEMP"]) / "leakcheck"),
                        ".github/leakcheck/main.go", ".github/leakcheck/matcher.go"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       env={"PATH": os.environ["PATH"], "HOME": "/nonexistent",
                            "GOENV": "off", "GOTOOLCHAIN": "local", "GO111MODULE": "off",
                            "GOCACHE": str(Path(os.environ["RUNNER_TEMP"]) / "go-cache")},
                       timeout=180)
        # Do not use fork URLs, checkout the head, install PR dependencies,
        # restore PR caches or consume artifacts created by untrusted jobs.
        subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "fetch",
                        "--no-tags", "https://github.com/" + REPO + ".git", head, base],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       env={"PATH": os.environ["PATH"], "HOME": "/nonexistent",
                            "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"},
                       timeout=180)
        metadata = Path(os.environ["RUNNER_TEMP"]) / "public-pr.json"
        metadata.write_text(json.dumps({"title": title, "body": body}))
        result = subprocess.run([str(Path(os.environ["RUNNER_TEMP"]) / "leakcheck"),
                                 os.getcwd(), base, head, str(metadata)],
                                capture_output=True, timeout=180,
                                env={"PATH": os.environ["PATH"],
                                     "NEVER_LEAK_PATTERNS": os.environ.get("NEVER_LEAK_PATTERNS", "")})
        # Even scanner crashes cannot expose runtime diagnostics or input.
        if result.returncode in (1, 2):
            sys.stdout.buffer.write(result.stdout)
        if result.returncode != 0:
            raise ValueError()
        if snapshot(api("/pulls/" + str(number))) != snapshot(pr):
            raise ValueError()
        status("success")
        return 0
    except Exception:
        print("rule scan-error in backstop line 0")
        if head is not None:
            try:
                status("failure")
            except Exception:
                pass  # A pending/missing status still blocks required-status merge.
        return 1


if __name__ == "__main__":
    sys.exit(main())
