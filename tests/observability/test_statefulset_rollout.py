#!/usr/bin/env python3
"""Exercise the deployed values expression with promtool (requires PyYAML)."""
from pathlib import Path
import shutil
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]
VALUES = ROOT / 'kubernetes/apps/observability/victoria-metrics/k8s-stack/helm/values.yaml'
RULE = 'KubeStatefulSetUpdateNotRolledOut'
expr = yaml.safe_load(VALUES.read_text())['defaultRules']['rules'][RULE]['spec']['expr']
labels = 'namespace="test",statefulset="model",job="kube-state-metrics",cluster="test"'


def scenario(name, *, replicas=2, updated=1, ready=2, partition=1,
             revision='new', alert=False, progressing=False, partition_labels=None):
    series = []

    def metric(name, value, extra='', values=None):
        series.append({'series': f'{name}{{{labels}{extra}}}',
                       'values': values or f'{value}+0x30'})

    metric('kube_statefulset_status_current_revision', 1, ',revision="old"')
    metric('kube_statefulset_status_update_revision', 1, f',revision="{revision}"')
    metric('kube_statefulset_replicas', replicas)
    metric('kube_statefulset_status_replicas_ready', ready)
    metric('kube_statefulset_status_replicas_updated', updated,
           values='0+0x17 1+0x3' if progressing else None)
    if partition is not None:
        series.append({'series': 'kube_leaderworkerset_rollout_partition{' +
                       (partition_labels or labels) + '}', 'values': f'{partition}+0x30'})
    expected = [{'exp_labels': dict(namespace='test', statefulset='model',
                                   job='kube-state-metrics', cluster='test', severity='warning'),
                 'exp_annotations': {}}] if alert else []
    return {'name': name, 'interval': '1m', 'input_series': series,
            'alert_rule_test': [{'eval_time': '20m', 'alertname': RULE, 'exp_alerts': expected}],
            'promql_expr_test': [{'expr': expr, 'eval_time': '20m',
                                 'exp_samples': [{'labels': '{' + labels + '}', 'value': replicas}] if alert else []}]}


cases = [
    scenario('fully rolled out', updated=2, partition=0, revision='old'),
    scenario('expected canary'),
    scenario('stalled above partition', updated=0, alert=True),
    scenario('unavailable canary', ready=1, alert=True),
    scenario('ordinary stalled rollout', partition=0, alert=True),
    scenario('missing metric fails open', partition=None, alert=True),
    scenario('all groups deliberately held', partition=2, updated=0),
    scenario('partition exceeds replica count', partition=3, updated=0),
    scenario('canary with extra updated groups', replicas=3, ready=3, updated=2),
    scenario('larger stalled canary', replicas=3, ready=3, updated=1, alert=True),
    scenario('still progressing', updated=1, partition=0, progressing=True),
    scenario('other cluster does not suppress', alert=True,
             partition_labels=labels.replace('cluster="test"', 'cluster="other"')),
    scenario('worker or unrelated set does not suppress', alert=True,
             partition_labels=labels.replace('statefulset="model"', 'statefulset="parent"')),
]
# KubeStatefulSetReplicasMismatch remains upstream and must still catch loss of
# readiness even after every replica has the new revision.
readiness_expr = '(kube_statefulset_status_replicas_ready != kube_statefulset_replicas) and (changes(kube_statefulset_status_replicas_updated[10m]) == 0)'
case = scenario('fully updated but unavailable', updated=2, ready=1, partition=0, revision='old')
case['promql_expr_test'].append({'expr': readiness_expr, 'eval_time': '20m',
                               'exp_samples': [{'labels': 'kube_statefulset_status_replicas_ready{' + labels + '}', 'value': 1}]})
cases.append(case)
with tempfile.TemporaryDirectory(prefix='statefulset-rules-') as directory:
    path = Path(directory)
    (path / 'rules.yaml').write_text(yaml.safe_dump({'groups': [{'name': 'test', 'rules': [
        {'alert': RULE, 'expr': expr, 'for': '15m', 'labels': {'severity': 'warning'}}]}]}))
    (path / 'tests.yaml').write_text(yaml.safe_dump({'rule_files': ['rules.yaml'],
                                                  'evaluation_interval': '1m', 'tests': cases}))
    subprocess.run([shutil.which('promtool') or 'promtool', 'test', 'rules', 'tests.yaml'],
                   cwd=path, check=True)
print(f'{len(cases)} StatefulSet rollout scenarios passed')
