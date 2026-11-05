"""Synthetic API/process fixtures. Failure messages never include fixture values."""

import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("check", Path(__file__).with_name("check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class Output(io.StringIO):
    def __init__(self):
        super().__init__()
        self.buffer = io.BytesIO()


class BackstopTest(unittest.TestCase):
    def exercise(self, change=False, scan_code=0, api_error=False, build_error=False):
        marker = "synthetic-forbidden-marker"
        pr = {"head": {"sha": "a" * 40}, "base": {"sha": "b" * 40},
              "title": "safe", "body": None}
        statuses, commands, reads = [], [], []

        def api(request, timeout):
            if request.data:
                statuses.append(json.loads(request.data)["state"])
                data = {}
            else:
                reads.append(request.full_url)
                data = copy.deepcopy(pr)
                if len(reads) == 2 and change:
                    data["body"] = marker
                if api_error:
                    raise ValueError(marker)
            return contextlib.closing(io.BytesIO(json.dumps(data).encode()))

        def command(args, **kwargs):
            commands.append((args, kwargs))
            if args[0] == "go" and build_error:
                raise ValueError(marker)
            if "leakcheck" in args[0]:
                return subprocess.CompletedProcess(args, scan_code,
                    b"rule fixture in PR body line 0\n" if scan_code else b"", marker.encode())
            return subprocess.CompletedProcess(args, 0)

        with tempfile.TemporaryDirectory() as tmp:
            event = Path(tmp) / "event.json"
            event.write_text('{"number": 42}')
            env = {"GITHUB_TOKEN": marker, "NEVER_LEAK_PATTERNS": marker,
                   "GITHUB_REPOSITORY": check.REPO, "GITHUB_EVENT_PATH": str(event),
                   "RUNNER_TEMP": tmp, "PATH": os.environ["PATH"]}
            output = Output()
            with patch.dict(os.environ, env, clear=True), \
                    patch.object(check.urllib.request, "urlopen", api), \
                    patch.object(check.subprocess, "run", command), \
                    contextlib.redirect_stdout(output):
                result = check.main()
        if marker in output.getvalue() or marker.encode() in output.buffer.getvalue():
            self.fail("entrypoint echoed fixture")
        for args, kwargs in commands:
            if marker in " ".join(args):
                self.fail("command argument exposes fixture")
            if args[0] in ("go", "git") and marker in str(kwargs["env"]):
                self.fail("build or fetch inherited credential")
        return result, statuses

    def test_success(self):
        result, statuses = self.exercise()
        self.assertTrue(result == 0 and statuses == ["pending", "success"], "status lifecycle")

    def test_fail_closed(self):
        for options in ({"change": True}, {"scan_code": 1}, {"scan_code": 2},
                        {"scan_code": -9}, {"build_error": True}):
            result, statuses = self.exercise(**options)
            self.assertTrue(result == 1 and statuses == ["pending", "failure"], "failure lifecycle")

    def test_api_error_no_echo(self):
        result, statuses = self.exercise(api_error=True)
        self.assertTrue(result == 1 and statuses == [], "API error must fail")


if __name__ == "__main__":
    unittest.main()
