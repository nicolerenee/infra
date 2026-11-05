#!/usr/bin/env python3
"""Keep an external source's root path inside the selected discovery graph.

flate can scan a foreign Kustomization's ./ against this checkout before
resolving its source. A root kustomize package prevents that fallback scan
from discovering other clusters. This ephemeral package changes no source
references, application manifests, renderer errors, or image pull behavior.
"""

import json
from pathlib import Path
import sys


def prepare(root, cluster):
    root = Path(root).resolve()
    if not cluster or Path(cluster).name != cluster or cluster in {'.', '..'}:
        raise ValueError('expected one cluster directory name')
    entry = root / 'kubernetes' / 'clusters' / cluster / 'flux'
    if not entry.is_dir():
        raise ValueError('cluster Flux entry does not exist')
    for name in ('kustomization.yaml', 'kustomization.yml', 'Kustomization'):
        if (root / name).exists():
            raise ValueError('refusing to replace an existing root kustomization')
        if (entry / name).exists():
            raise ValueError('cluster entry is now a package; review discovery root setup')
    resources = sorted(str(p.relative_to(root)) for p in entry.iterdir()
                       if p.is_file() and p.suffix in {'.yaml', '.yml'})
    if not resources:
        raise ValueError('empty cluster Flux entry')
    # JSON is YAML; avoid parsing or rewriting any production manifest.
    (root / 'kustomization.yaml').write_text(json.dumps({
        'apiVersion': 'kustomize.config.k8s.io/v1beta1',
        'kind': 'Kustomization', 'resources': resources,
    }, indent=2) + '\n')


if __name__ == '__main__':
    prepare(Path.cwd(), sys.argv[1])
