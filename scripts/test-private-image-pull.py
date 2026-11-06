#!/usr/bin/env python3
"""Exercise the private-image pull helper and the workflow's routing against a fake API."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/pull-private-image.sh'
WORKFLOW = ROOT / '.github/workflows/image-pull-extract-pull.yaml'
PRIVATE = 'ghcr.io/freckleapps/udev-queue-collector@sha256:' + 'a' * 64
PUBLIC = 'ghcr.io/home-operations/radarr:6.0.0'

# Stands in for curl against the Kubernetes API. Responses come from
# scenario.json; every request is appended to requests.jsonl.
FAKE_CURL = r'''#!/usr/bin/env python3
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parent
scenario = json.loads((root / 'scenario.json').read_text())
args = sys.argv[1:]
method, headers, data, out, url = 'GET', [], None, None, None
i = 0
while i < len(args):
    a = args[i]
    if a == '-X': method = args[i + 1]; i += 2; continue
    if a == '-H': headers.append(args[i + 1]); i += 2; continue
    if a == '--data-binary': data = args[i + 1]; i += 2; continue
    if a == '-o': out = args[i + 1]; i += 2; continue
    if a == '--cacert': i += 2; continue
    if a.startswith('-'): i += 1; continue
    url = a; i += 1
with open(root / 'requests.jsonl', 'a') as f:
    f.write(json.dumps(dict(method=method, url=url, headers=headers, data=data)) + '\n')
path = url.split('://', 1)[1].split('/', 1)[1]
path = '/' + path
def count(name):
    state = root / name
    n = int(state.read_text()) if state.exists() else 0
    state.write_text(str(n + 1))
    return n
def seq(key, name):
    values = scenario[key]
    return values[min(count(name), len(values) - 1)]
if method == 'GET' and path == '/api/v1/nodes':
    body = {'items': scenario['nodes']}
elif method == 'GET' and '/secrets?' in path:
    body = {'items': [{'metadata': {'name': 'ghcr-pull'}}] * scenario['secrets']}
elif method == 'POST' and path.endswith('/pods'):
    body = {'metadata': {'name': 'image-pull-x7k2q'}}
elif method == 'GET' and '/pods/' in path:
    body = {'status': {'phase': seq('phases', 'phase-calls')}}
elif method == 'GET' and '/events?' in path:
    body = {'items': seq('events', 'event-calls')}
elif method == 'DELETE':
    body = {}
else:
    sys.stderr.write('unexpected request ' + method + ' ' + path + '\n')
    sys.exit(22)
if out:
    pathlib.Path(out).write_text(json.dumps(body))
else:
    sys.stdout.write(json.dumps(body))
'''


def node(name, ip):
    return {'metadata': {'name': name},
            'status': {'addresses': [{'type': 'Hostname', 'address': name},
                                     {'type': 'InternalIP', 'address': ip}]}}


PULL_401 = {'type': 'Warning', 'reason': 'Failed',
            'message': f'Failed to pull image "{PRIVATE}": failed to authorize: 401 Unauthorized'}


class Sandbox:
    def __init__(self, directory, scenario):
        self.root = Path(directory)
        (self.root / 'scenario.json').write_text(json.dumps(scenario))
        for name, text in (('curl', FAKE_CURL),
                           ('sleep', '#!/bin/sh\nexit 0\n'),
                           ('talosctl', '#!/bin/sh\necho "$*" >> talosctl.calls\n')):
            tool = self.root / name
            tool.write_text(text)
            tool.chmod(0o755)
        sa = self.root / 'sa'
        sa.mkdir()
        (sa / 'ca.crt').write_text('ca')
        (sa / 'token').write_text('token')
        self.env = {**os.environ, 'PATH': f'{self.root}:{os.environ["PATH"]}',
                    'SA_DIR': str(sa), 'PULL_POLL_SECONDS': '0'}

    def requests(self):
        path = self.root / 'requests.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run(self, args, **env):
        return subprocess.run(args, cwd=self.root, env={**self.env, **env},
                              capture_output=True, text=True, timeout=30)


SCENARIO = dict(nodes=[node('cn01', '192.0.2.11'), node('cn02', '192.0.2.12')], secrets=1,
                phases=['Pending', 'Running'], events=[[]])


class HelperTests(unittest.TestCase):
    def helper(self, scenario=None, image=PRIVATE, ip='192.0.2.12', **env):
        with tempfile.TemporaryDirectory() as directory:
            box = Sandbox(directory, {**SCENARIO, **(scenario or {})})
            result = box.run(['bash', str(HELPER), image, ip], **env)
            return result, box.requests()

    def test_pulls_through_kubelet_on_target_node(self):
        result, requests = self.helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'Pulled {PRIVATE} on cn02', result.stdout)
        post = next(r for r in requests if r['method'] == 'POST')
        self.assertTrue(post['url'].endswith('/api/v1/namespaces/image-pull-check/pods'))
        pod = json.loads(post['data'])['spec']
        self.assertEqual(pod['nodeName'], 'cn02')
        self.assertEqual(pod['imagePullSecrets'], [{'name': 'ghcr-pull'}])
        self.assertEqual(pod['volumes'], [{'name': 'image', 'image': {'reference': PRIVATE, 'pullPolicy': 'Always'}}])
        # The private image is only mounted; the one container is pause.
        self.assertEqual([c['image'] for c in pod['containers']], ['registry.k8s.io/pause:3.10'])
        self.assertNotIn('command', pod['containers'][0])
        self.assertFalse(pod['automountServiceAccountToken'])
        self.assertEqual(requests[-1]['method'], 'DELETE')

    def test_secret_is_read_as_metadata_only(self):
        _, requests = self.helper()
        secret = next(r for r in requests if '/secrets?' in r['url'])
        self.assertIn('fieldSelector=metadata.name%3Dghcr-pull', secret['url'])
        self.assertIn('Accept: application/json;as=PartialObjectMetadataList;g=meta.k8s.io;v=v1', secret['headers'])

    def test_pull_failure_event_fails_and_cleans_up(self):
        result, requests = self.helper(dict(phases=['Pending'], events=[[PULL_401]]))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('::error::kubelet could not pull', result.stdout)
        self.assertIn('401 Unauthorized', result.stdout)
        self.assertEqual(requests[-1]['method'], 'DELETE')

    def test_unrelated_warning_does_not_fail(self):
        noise = {'type': 'Warning', 'reason': 'DNSConfigForming', 'message': 'nameserver limits'}
        result, _ = self.helper(dict(events=[[noise]]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_pod_fails(self):
        result, _ = self.helper(dict(phases=['Failed']))
        self.assertNotEqual(result.returncode, 0)

    def test_timeout_fails(self):
        result, requests = self.helper(dict(phases=['Pending']), PULL_TIMEOUT_SECONDS='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('timed out', result.stdout)
        self.assertEqual(requests[-1]['method'], 'DELETE')

    def test_missing_secret_fails_before_creating_pod(self):
        result, requests = self.helper(dict(secrets=0))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ghcr-pull is missing', result.stdout)
        self.assertFalse([r for r in requests if r['method'] == 'POST'])

    def test_unknown_node_fails_before_creating_pod(self):
        result, requests = self.helper(ip='192.0.2.99')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no node has InternalIP', result.stdout)
        self.assertFalse([r for r in requests if r['method'] == 'POST'])

    def test_rejects_refs_outside_private_org_or_with_json_metacharacters(self):
        for image in (PUBLIC, 'ghcr.io/freckleapps/x", "evil": "1',
                      'ghcr.io/freckleapps/x:tag\n', 'ghcr.io/freckleapps/'):
            with self.subTest(image=image):
                result, requests = self.helper(image=image)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(requests, [])


class WorkflowRoutingTests(unittest.TestCase):
    def step(self):
        source = WORKFLOW.read_text().split('      - name: Pull Image\n', 1)[1]
        source = source.split('        run: |\n', 1)[1]
        return textwrap.dedent(source.split('\n      - name:', 1)[0])

    def route(self, image, scenario=None):
        with tempfile.TemporaryDirectory() as directory:
            box = Sandbox(directory, {**SCENARIO, **(scenario or {})})
            tools = box.root / '.image-pull-tools/scripts'
            tools.mkdir(parents=True)
            (tools / 'pull-private-image.sh').symlink_to(HELPER)
            result = box.run(['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', self.step()],
                             IMAGE=image, NODE='192.0.2.11')
            calls = box.root / 'talosctl.calls'
            return result, box.requests(), calls.read_text().splitlines() if calls.exists() else []

    def test_public_image_keeps_talos_pull(self):
        result, requests, talos = self.route(PUBLIC)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(talos, [f'--nodes 192.0.2.11 image pull {PUBLIC}'])
        self.assertEqual(requests, [])

    def test_private_image_uses_kubelet_not_talos(self):
        result, requests, talos = self.route(PRIVATE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(talos, [])
        pod = json.loads(next(r for r in requests if r['method'] == 'POST')['data'])
        self.assertEqual(pod['spec']['nodeName'], 'cn01')

    def test_private_pull_failure_fails_the_step(self):
        result, _, talos = self.route(PRIVATE, dict(phases=['Pending'], events=[[PULL_401]]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(talos, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
