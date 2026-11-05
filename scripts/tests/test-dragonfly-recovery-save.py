"""Exercise the actual manual Job scripts without a cluster or credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FAKE_CLI = r'''#!/usr/bin/env python3
import os, pathlib, sys
p = pathlib.Path(os.environ["CALLS"])
calls = p.read_text().splitlines() if p.exists() else []
args = sys.argv[1:]
assert args[:4] == ["-e", "--raw", "-h", "192.0.2.1"]
command = " ".join(args[4:])
p.write_text("\n".join(calls + [command]) + "\n")
scenario = os.environ["SCENARIO"]
saved = "SAVE DF c694-pre-v2-1" in calls
if command == "ROLE":
    print("slave" if scenario == "replica" or (saved and scenario == "demotion") else "master")
elif command == "INFO server":
    if scenario == "info-error":
        print("uptime_in_seconds:500")
        sys.exit(1)
    if scenario != "missing-uptime":
        uptime = "1" if (saved and scenario == "restart") else "500"
        if scenario == "young": uptime = "10"
        if scenario == "invalid-uptime": uptime = "bad"
        print("uptime_in_seconds:" + uptime + "\r")
elif command == "SAVE DF c694-pre-v2-1":
    if scenario == "save-error": sys.exit(1)
    print("BUSY" if scenario == "save-not-ok" else "OK\r")
else:
    sys.exit(2)
'''


class RecoverySave(unittest.TestCase):
    def test_faults_and_success(self):
        for namespace in ("nautobot", "hedgehog"):
            folder = ROOT / "kubernetes/apps" / namespace / "queue"
            template = (folder / "recovery-save-c694.yaml.template").read_text()
            # Extract the actual YAML block scalar, preserving shell indentation.
            block = template.split("            - |\n", 1)[1].split("          env:", 1)[0]
            script = "\n".join(line[14:] for line in block.splitlines())
            self.assertIn("activeDeadlineSeconds: 120", template)
            self.assertNotIn("recovery-save-c694.yaml.template", (folder / "kustomization.yaml").read_text())
            for scenario in ("ok", "replica", "missing-uptime", "invalid-uptime",
                             "info-error", "young", "restart", "demotion",
                             "save-error", "save-not-ok", "unset-host", "service-host"):
                with self.subTest(namespace=namespace, scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                    tmp = Path(tmp)
                    cli = tmp / "redis-cli"
                    cli.write_text(FAKE_CLI)
                    cli.chmod(0o755)
                    calls = tmp / "calls"
                    host = "" if scenario == "unset-host" else "192.0.2.1"
                    if scenario == "service-host": host = "queue-service"
                    env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ["PATH"],
                               RECOVERY_HOST=host, SCENARIO=scenario, CALLS=str(calls))
                    result = subprocess.run(["/bin/sh", "-ec", script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    commands = calls.read_text().splitlines() if calls.exists() else []
                    self.assertEqual(result.returncode == 0, scenario == "ok", result.stdout + result.stderr)
                    preflight_failures = {"replica", "missing-uptime", "invalid-uptime", "info-error",
                                          "young", "unset-host", "service-host"}
                    self.assertEqual(commands.count("SAVE DF c694-pre-v2-1"),
                                     0 if scenario in preflight_failures else 1)
                    if scenario != "ok":
                        self.assertIn("Recovery save", result.stderr)
                        self.assertIn("stopped at", result.stderr)


if __name__ == "__main__":
    unittest.main()
