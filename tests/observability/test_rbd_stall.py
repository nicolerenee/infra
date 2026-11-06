#!/usr/bin/env python3
"""Run the actual VMRule through vmalert-tool (PyYAML required).

Usage: python3 tests/observability/test_rbd_stall.py /path/to/vmalert-tool
The fixture uses synthetic labels only. Historical incident replays belong in
private operational evidence, not in this public repository.
"""
from copy import deepcopy
from pathlib import Path
import subprocess
import sys
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'kubernetes/apps/observability/victoria-metrics/k8s-stack/node-storage-rules.yaml'
GROUP = yaml.safe_load(SOURCE.read_text())['spec']['groups'][0]
RULE = next(r for r in GROUP['rules'] if r['alert'] == 'NodeRBDIOStalled')
BASE = dict(cluster='test', instance='test:9100', device='rbd0',
            service='vm-k8s-stack-prometheus-node-exporter')
COUNTERS = [f'node_disk_{kind}_completed_total' for kind in ('reads', 'writes', 'discards')]


def series(metric, values, **labels):
    labels = BASE | labels
    return dict(series=metric + '{' + ','.join(f'{k}="{v}"' for k, v in labels.items()) + '}',
                values=values)


def case(name, queue='2+0x24', counters=None, *, fires=False, extra=None, join=True,
         checks=None, interval='20s'):
    inputs = [series('node_disk_io_now', queue)]
    counters = counters or ['96+0x24', '0+0x24', '0+0x24']
    inputs += [series(metric, values) for metric, values in zip(COUNTERS, counters)
               if values is not None]
    if join:
        labels = {k: v for k, v in BASE.items() if k != 'device'} | dict(nodename='test-node')
        inputs.append(dict(series='node_uname_info{' + ','.join(
            f'{k}="{v}"' for k, v in labels.items()) + '}', values='1+0x24'))
    inputs += extra or []
    labels = {k: BASE[k] for k in ('cluster', 'instance', 'device')}
    labels |= dict(node='test-node', severity='warning')
    expected = [dict(exp_labels=labels, exp_annotations={})] if fires else []
    # Evaluate the full hold period at every rule evaluation, including startup.
    tests = [dict(eval_time=f'{t}s', alertname=RULE['alert'],
                  exp_alerts=expected if t >= 180 else [])
             for t in range(0, 301, 30)]
    if checks is not None:
        tests = [dict(eval_time=f'{t}s', alertname=RULE['alert'],
                      exp_alerts=expected if firing else []) for t, firing in checks]
    return dict(name=name, interval=interval, input_series=inputs, alert_rule_test=tests)


cases = [
    case('fully sampled nonzero queue and zero completions', fires=True),
    case('one sample then stale', queue='2 stale', counters=['96 stale', '0 stale', '0 stale']),
    case('one sample without stale marker', queue='2', counters=['96', '0', '0']),
    case('sparse queue', queue='2 _ _ 2 _ _ 2 _ _ 2 _ _ 2 _ _ 2'),
    case('sparse counter', counters=['96 _ _ 96 _ _ 96 _ _ 96 _ _ 96', '0+0x24', '0+0x24']),
    case('one missing scrape in each window', queue='2 2 _ 2 2 2 _ 2 2 2 _ 2 2 2 _ 2'),
    case('burst samples with a long gap', interval='10s',
         queue='2 2 2 2 2 2 _ _ _ _ 2 2 2 2 2 2 _ _ _ _ 2 2 2 2 2 2 _ _ _ _ 2'),
    case('short dense history', interval='10s', queue='2 2 2 2 2 2 stale'),
    case('missing discard counter', counters=['96+0x24', '0+0x24', None]),
    case('stale completion counter', counters=['96+0x24', '0+0x24', '0 stale']),
    case('idle queue', queue='0+0x24'),
    case('queue drains', queue='2 2 2 0 2 2 2 0 2 2 2 0 2 2 2 0'),
    case('no node identity', join=False),
    case('recovery resets hold', queue='2+0x8 0+0x15'),
    # Fully sampled history disappears after t=220; count still reaches six at
    # t=240, so the freshness/instant guards must clear the firing alert.
    case('fully sampled then stale', queue='2+0x11 stale',
         counters=['96+0x11 stale', '0+0x11 stale', '0+0x11 stale'], fires=True,
         checks=[(180, True), (210, True), (240, False), (270, False), (300, False)]),
    case('fully sampled then stops without stale marker', queue='2+0x11',
         counters=['96+0x11', '0+0x11', '0+0x11'], fires=True,
         checks=[(180, True), (210, True), (270, False), (300, False)]),
    # Each raw exporter history is too short; pooling would incorrectly pass.
    case('replacement exporter histories cannot pool coverage', queue='2+0x2 stale',
         counters=['96+0x2 stale', '0+0x2 stale', '0+0x2 stale'],
         extra=[series(m, '_ _ _ 2+0x2 stale', pod='replacement')
                for m in ['node_disk_io_now'] + COUNTERS]),
]
for index, counter in enumerate(COUNTERS):
    values = ['96+0x24', '0+0x24', '0+0x24']
    values[index] = '96+1x24'
    cases.append(case(f'progressing {counter}', counters=values))

# Keep the real expression, labels, hold and evaluation cadence; omit only
# human annotations so wording changes do not rewrite every expected alert.
rule = deepcopy(RULE)
rule['annotations'] = {}
with tempfile.TemporaryDirectory(prefix='rbd-stall-') as tmp:
    tmp = Path(tmp)
    (tmp / 'rules.yaml').write_text(yaml.safe_dump(dict(groups=[dict(
        name=GROUP['name'], interval=GROUP['interval'], rules=[rule])]), sort_keys=False))
    (tmp / 'tests.yaml').write_text(yaml.safe_dump(dict(rule_files=['rules.yaml'],
        evaluation_interval=GROUP['interval'], tests=cases), sort_keys=False))
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else 'vmalert-tool', 'unittest',
                    '-files', str(tmp / 'tests.yaml'), '-disableAlertgroupLabel'],
                   cwd=tmp, check=True)
print(f'Passed {len(cases)} RBD alert cases')
