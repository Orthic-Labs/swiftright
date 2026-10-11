#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from factory.core.artifacts import load_artifact
from factory.pipeline import workflow
from factory.pipeline.archive_reader import ArchiveByteReader

ROOT = Path(__file__).resolve().parents[3]
MAC = ROOT / 'factory/native/macos/evidence/20261010-gate-seeded/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258'
CASE_ID = 'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258'


def digest(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class MutatingReader:
    def __init__(self, base):
        self.base = base

    def __call__(self, *, capture, reference):
        raw = self.base(capture=capture, reference=reference)
        if reference['path'].endswith('/run-001/capture.json'):
            value = json.loads(raw.decode('utf-8'))
            value['id'] += '.reader-return-fault'
            return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True).encode('utf-8')
        return raw


def main() -> dict:
    cases = [x for x in load_artifact(ROOT / 'factory/pipeline/gate-pilot/seed-cases.json') if x['id'] == CASE_ID]
    assert_true(len(cases) == 1, 'seed case missing')
    artifact_reader = ArchiveByteReader(mac_roots=[ROOT])
    baseline = workflow.collect(cases, [MAC], reader=artifact_reader)
    assert_true(len(baseline['captures']) == 20, f"baseline count {len(baseline['captures'])}")
    assert_true(not baseline['diagnostics'], f"baseline diagnostics {baseline['diagnostics'][:1]}")

    fault = workflow.collect(cases, [MAC], reader=MutatingReader(artifact_reader))
    assert_true(len(fault['captures']) == 19, f"fault count {len(fault['captures'])}")
    reasons = [row['reason'] for row in fault['diagnostics']]
    assert_true(any('differing from expected hash' in reason for reason in reasons), str(reasons))

    origin_reader = ArchiveByteReader(mac_roots=[MAC])
    plan = ROOT / 'factory/pipeline/gate-pilot/gate-results.json'
    cases_path = ROOT / 'factory/pipeline/inputs/cases.json'
    tuple_path = ROOT / 'factory/pipeline/inputs/observed-tuple.json'
    config_path = ROOT / 'factory/pipeline/inputs/acceptance-candidate.json'
    manifests = ROOT / 'factory/pipeline/manifests'
    with tempfile.TemporaryDirectory(prefix='workflow-reader-repair-v1-') as scratch:
        replay = workflow.gate_evidence(Path(scratch) / 'gate', plan, cases_path, [MAC], tuple_path,
                                        config_path, manifests, origin_reader=origin_reader,
                                        artifact_reader=artifact_reader)
    assert_true(replay['nativeCaptureCount'] == 20, str(replay))
    assert_true(replay['parityGranted'] is False, str(replay))
    return {
        'verdict': 'PASS_READER_BOUND_ARTIFACT_REPLAY',
        'baselineCollected': len(baseline['captures']),
        'mutationCollected': len(fault['captures']),
        'mutationReason': reasons[0],
        'gateEvidenceNativeCaptureCount': replay['nativeCaptureCount'],
        'gateEvidenceParityGranted': replay['parityGranted'],
        'artifactReader': 'ArchiveByteReader(mac_roots=repo-root)',
        'originReader': 'ArchiveByteReader(mac_roots=mac-capture-root)',
        'source': 'factory/pipeline/workflow.py',
    }


if __name__ == '__main__':
    print(json.dumps(main(), indent=2, sort_keys=True))
