#!/usr/bin/env python3
"""Exercise the workflow's actual Gather Images shell with deterministic fetch failures."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/image-pull-extract-pull.yaml'


class RenderRetryTests(unittest.TestCase):
    def run_render(self, attempts):
        source = WORKFLOW.read_text().split('      - name: Gather Images\n        run: |\n', 1)[1]
        source = textwrap.dedent(source.split('\n      - name:', 1)[0])
        source = re.sub(r'\$\{\{ inputs.cluster \}\}', 'test-cluster', source)
        source = re.sub(r'\$\{\{ matrix.branch \}\}', 'pull', source)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            flate = root / 'flate'
            flate.write_text('''#!/usr/bin/env python3
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parent
state = root / 'calls'
count = int(state.read_text()) if state.exists() else 0
state.write_text(str(count + 1))
attempts = json.loads((root / 'attempts.json').read_text())
a = attempts[min(count, len(attempts) - 1)]
sys.stdout.write(a['output'])
sys.stderr.write(a['error'])
sys.exit(a['rc'])
''')
            flate.chmod(0o755)
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> sleeps\n')
            sleep.chmod(0o755)
            (root / 'attempts.json').write_text(json.dumps(attempts))
            result = subprocess.run(
                ['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', source],
                cwd=root, env={**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}',
                               'GITHUB_STEP_SUMMARY': str(root / 'summary')},
                capture_output=True, text=True, timeout=10,
            )
            return (result, int((root / 'calls').read_text()),
                    (root / 'sleeps').read_text().splitlines() if (root / 'sleeps').exists() else [],
                    (root / 'images.json').read_text())

    @staticmethod
    def attempt(rc=0, output='["example.test/app:1"]', error=''):
        return dict(rc=rc, output=output, error=error)

    def test_schema_fetch_recovers(self):
        failure = self.attempt(1, '["partial"]', 'schema fetch timed out\nreconcile completed with 1 failure\n')
        result, calls, sleeps, output = self.run_render([failure, self.attempt()])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((calls, sleeps), (2, ['10']))
        self.assertEqual(json.loads(output), ['example.test/app:1'])

    def test_chart_fetch_recovers_after_two_failures(self):
        failure = self.attempt(1, '', 'oras fetch ghcr.io chart failed\nreconcile completed with 2 failures\n')
        result, calls, sleeps, _ = self.run_render([failure, failure, self.attempt()])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((calls, sleeps), (3, ['10', '30']))

    def test_persistent_render_failure_stays_red(self):
        result, calls, sleeps, _ = self.run_render([
            self.attempt(1, '[]', 'invalid manifest\nreconcile completed with 1 failure\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((calls, sleeps), (3, ['10', '30']))
        self.assertIn('::error::', result.stdout)

    def test_missing_summary_stays_red(self):
        result, calls, sleeps, _ = self.run_render([self.attempt(1, '[]', 'unexpected termination\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((calls, sleeps), (3, ['10', '30']))

    def test_blocked_only_accepted_without_retry(self):
        for summary in ['reconcile completed with 0 failures (+12 blocked)\n',
                        'reconcile completed with 0 failures\n']:
            with self.subTest(summary=summary):
                result, calls, sleeps, _ = self.run_render([self.attempt(1, '[]', summary)])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((calls, sleeps), (1, []))
                self.assertIn('::warning::', result.stdout)

    def test_invalid_output_stays_red(self):
        for output in ['["truncated"', '{}', '']:
            with self.subTest(output=output):
                result, calls, sleeps, _ = self.run_render([self.attempt(output=output)])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((calls, sleeps), (1, []))

    def test_success_without_retry(self):
        result, calls, sleeps, output = self.run_render([self.attempt(output='[]')])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((calls, sleeps, json.loads(output)), (1, [], []))


if __name__ == '__main__':
    unittest.main()
