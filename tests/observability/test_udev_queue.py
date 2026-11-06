#!/usr/bin/env python3
"""Exercise queue rules and hold times with promtool (requires PyYAML)."""
from pathlib import Path
import copy
import shutil
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'kubernetes/apps/observability/victoria-metrics/k8s-stack/node-storage-rules.yaml'
GROUP = next(g for g in yaml.safe_load(SOURCE.read_text())['spec']['groups']
             if g['name'] == 'node-udev-queue')
COMMON = 'cluster="test",namespace="observability",pod="vm-k8s-stack-prometheus-node-exporter-pilot"'
EXPORTER = COMMON + ',service="vm-k8s-stack-prometheus-node-exporter"'
FAILED = 'NodeUdevQueueCollectionFailed'
UNKNOWN = 'NodeUdevQueueTelemetryUnavailable'
PENDING = 'NodeUdevQueuePersistent'


def scenario(name, *, changes=None, omit=(), expected=(), eval_time='6m', inventory=True,
             other_service=False, duplicate_info=False, other_cluster=False):
    values = {
        'node_udev_queue_collection_success': '1+0x20',
        'node_udev_queue_collection_timestamp_seconds': '0+30x20',
        'node_udev_queue_last_success_timestamp_seconds': '0+30x20',
        'node_udev_queue_present': '0+0x20',
        'node_udev_queue_age_seconds': '0+0x20',
        'node_udev_queue_mtime_seconds': '0+0x20',
        'node_textfile_scrape_error': '0+0x20',
    }
    values.update(changes or {})
    labels = EXPORTER.replace('vm-k8s-stack-prometheus-node-exporter"', 'other-exporter"') if other_service else EXPORTER
    if other_cluster:
        labels = labels.replace('cluster="test"', 'cluster="other"')
    series = [{'series': f'{metric}{{{labels}}}', 'values': value}
              for metric, value in values.items() if metric not in omit]
    if inventory:
        series.append({'series': 'kube_pod_container_resource_requests{' + COMMON +
                       ',job="kube-state-metrics",container="udev-queue-collector",resource="memory"}',
                       'values': '8388608+0x20'})
    series.append({'series': 'kube_pod_info{' + COMMON + ',job="kube-state-metrics",node="test-node",instance="ksm-a"}',
                   'values': '1+0x20'})
    if duplicate_info:
        series.append({'series': series[-1]['series'].replace('ksm-a', 'ksm-b'), 'values': '1+0x20'})
    expected_samples = [{'labels': 'ALERTS{' + COMMON + f',node="test-node",severity="warning",alertname="{alert}",alertstate="firing"}}',
                         'value': 1} for alert in expected]
    return {'name': name, 'interval': '30s', 'input_series': series,
            'promql_expr_test': [{'expr': 'ALERTS{alertstate="firing"}', 'eval_time': eval_time,
                                 'exp_samples': expected_samples}]}

cases = [
    scenario('idle and fresh'),
    scenario('pending older than two minutes', changes={'node_udev_queue_present': '1+0x20',
             'node_udev_queue_age_seconds': '180+0x20'}, expected=[PENDING]),
    scenario('persistence hold not elapsed', changes={'node_udev_queue_present': '1+0x20',
             'node_udev_queue_age_seconds': '180+0x20'}, eval_time='30s'),
    scenario('young pending queue', changes={'node_udev_queue_present': '1+0x20',
             'node_udev_queue_age_seconds': '90+0x20'}),
    scenario('stale writer suppresses frozen pending age', changes={'node_udev_queue_present': '1+0x20',
             'node_udev_queue_age_seconds': '180+0x20',
             'node_udev_queue_collection_timestamp_seconds': '0+0x20',
             'node_udev_queue_last_success_timestamp_seconds': '0+0x20'}, expected=[UNKNOWN]),
    scenario('future attempt', changes={'node_udev_queue_collection_timestamp_seconds': '600+30x20'}, expected=[UNKNOWN]),
    scenario('future success', changes={'node_udev_queue_last_success_timestamp_seconds': '600+30x20'}, expected=[UNKNOWN]),
    scenario('old last success', changes={'node_udev_queue_last_success_timestamp_seconds': '0+0x20'}, expected=[UNKNOWN]),
    scenario('failed inspection omits queue state', changes={'node_udev_queue_collection_success': '0+0x20',
             'node_udev_queue_last_success_timestamp_seconds': '0+0x20'},
             omit=['node_udev_queue_present', 'node_udev_queue_age_seconds', 'node_udev_queue_mtime_seconds'],
             expected=[FAILED, UNKNOWN]),
    scenario('no textfile even while exporter runs', omit=['node_udev_queue_collection_success',
             'node_udev_queue_collection_timestamp_seconds', 'node_udev_queue_last_success_timestamp_seconds',
             'node_udev_queue_present', 'node_udev_queue_age_seconds', 'node_udev_queue_mtime_seconds'], expected=[UNKNOWN]),
    scenario('unknown hold not elapsed', omit=['node_udev_queue_collection_success'], eval_time='90s'),
    scenario('textfile parse error', changes={'node_textfile_scrape_error': '1+0x20'}, expected=[UNKNOWN]),
    scenario('missing queue presence on success', omit=['node_udev_queue_present'], expected=[UNKNOWN]),
    scenario('missing queue age on success', omit=['node_udev_queue_age_seconds'], expected=[UNKNOWN]),
    scenario('future queue mtime', changes={'node_udev_queue_mtime_seconds': '600+30x20'}, expected=[UNKNOWN]),
    scenario('future mtime suppresses persistence', changes={'node_udev_queue_mtime_seconds': '600+30x20',
             'node_udev_queue_present': '1+0x20', 'node_udev_queue_age_seconds': '180+0x20'}, expected=[UNKNOWN]),
    scenario('duplicate KSM scrape identity', duplicate_info=True),
    scenario('unupdated pods excluded', inventory=False, omit=['node_udev_queue_collection_success']),
    scenario('other exporter excluded', other_service=True, expected=[UNKNOWN]),
    scenario('other cluster excluded', other_cluster=True, expected=[UNKNOWN]),
]
# Annotations are prose; retain the actual expressions, labels and holds.
group = copy.deepcopy(GROUP)
for rule in group['rules']:
    rule.pop('annotations', None)
with tempfile.TemporaryDirectory(prefix='udev-queue-') as directory:
    path = Path(directory)
    (path / 'rules.yaml').write_text(yaml.safe_dump({'groups': [group]}))
    (path / 'tests.yaml').write_text(yaml.safe_dump({'rule_files': ['rules.yaml'],
                                                   'evaluation_interval': '30s', 'tests': cases}))
    subprocess.run([shutil.which('promtool') or 'promtool', 'test', 'rules', str(path / 'tests.yaml')],
                   cwd=path, check=True)
print(f'{len(cases)} queue rule scenarios passed')
