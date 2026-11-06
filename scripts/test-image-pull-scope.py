#!/usr/bin/env python3
"""Regression: foreign root paths cannot add another cluster's images."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('scope', Path(__file__).with_name('prepare-image-pull-root.py'))
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / '.git').mkdir()
        for cluster in ('one', 'two'):
            entry = f'kubernetes/clusters/{cluster}/flux'
            self.write(f'{entry}/app.yaml', {
                'apiVersion': 'kustomize.toolkit.fluxcd.io/v1', 'kind': 'Kustomization',
                'metadata': {'name': f'app-{cluster}', 'namespace': 'default'},
                'spec': {'path': f'./apps/{cluster}', 'interval': '1h',
                         'sourceRef': {'kind': 'GitRepository', 'name': 'flux-system', 'namespace': 'flux-system'}},
            })
            self.write(f'apps/{cluster}/pod.yaml', {
                'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': cluster},
                'spec': {'containers': [{'name': 'app', 'image': f'registry.example/{cluster}:1'}],
                         'initContainers': [{'name': 'init', 'image': f'registry.example/{cluster}-init:1'}]},
            })
            self.write(f'apps/{cluster}/kustomization.yaml', {
                'apiVersion': 'kustomize.config.k8s.io/v1beta1', 'kind': 'Kustomization', 'resources': ['pod.yaml'],
            })
        # A foreign bundle rooted at ./ is the original cross-cluster trigger.
        self.write('kubernetes/clusters/one/flux/foreign.yaml', {
            'apiVersion': 'kustomize.toolkit.fluxcd.io/v1', 'kind': 'Kustomization',
            'metadata': {'name': 'foreign', 'namespace': 'default'},
            'spec': {'path': './', 'interval': '1h',
                     'sourceRef': {'kind': 'OCIRepository', 'name': 'foreign'}},
        })
        self.write('kubernetes/clusters/one/flux/source.yaml', {
            'apiVersion': 'source.toolkit.fluxcd.io/v1', 'kind': 'OCIRepository',
            'metadata': {'name': 'foreign', 'namespace': 'default'},
            'spec': {'url': 'oci://registry.invalid/private/bundle', 'interval': '1h',
                     'ref': {'tag': '1'}, 'secretRef': {'name': 'runtime-only'}},
        })

    def write(self, path, doc):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(doc))

    def images(self):
        result = subprocess.run([
            os.environ.get('FLATE', 'flate'), 'get', 'images', '--path',
            'kubernetes/clusters/one/flux', '--allow-missing-secrets', '--output', 'json', '--no-progress',
        ], cwd=self.root, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_foreign_root_reproduces_then_stays_in_cluster(self):
        self.assertIn('registry.example/two:1', self.images())
        scope.prepare(self.root, 'one')
        self.assertEqual(self.images(), ['registry.example/one-init:1', 'registry.example/one:1'])

    def test_local_render_error_still_fails(self):
        scope.prepare(self.root, 'one')
        (self.root / 'apps/one/pod.yaml').write_text('invalid: [')
        result = subprocess.run([
            os.environ.get('FLATE', 'flate'), 'get', 'images', '--path',
            'kubernetes/clusters/one/flux', '--allow-missing-secrets', '--output', 'json', '--no-progress',
        ], cwd=self.root, capture_output=True, text=True, timeout=60)
        self.assertNotEqual(result.returncode, 0)

    def test_root_is_exact_entry_and_other_files_unchanged(self):
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*.yaml')}
        scope.prepare(self.root, 'one')
        root = json.loads((self.root / 'kustomization.yaml').read_text())
        self.assertEqual(root['resources'], sorted(str(p) for p in before if str(p).startswith('kubernetes/clusters/one/flux/')))
        for path, content in before.items():
            self.assertEqual((self.root / path).read_bytes(), content)

    def test_rejects_wrong_cluster_and_existing_packages(self):
        for cluster in ('missing', '../two', '', '..'):
            with self.subTest(cluster=cluster), self.assertRaises(ValueError):
                scope.prepare(self.root, cluster)
        scope.prepare(self.root, 'one')
        with self.assertRaises(ValueError):
            scope.prepare(self.root, 'one')


if __name__ == '__main__':
    unittest.main()
