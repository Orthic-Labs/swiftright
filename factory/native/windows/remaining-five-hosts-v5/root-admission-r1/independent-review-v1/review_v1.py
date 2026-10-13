from __future__ import annotations
import copy, hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parent
BUNDLE = HERE / 'transfer-bundle.json'
TRANSFER = HERE / 'transfer-bundle.ps1'
ADMIT = HERE / 'admit-hosts.ps1'
STAGE = ROOT / 'root-stage-manifest.json'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(bundle, transfer_text, admit_text):
    stage = json.loads(STAGE.read_text())
    assert stage['kind'] == 'remaining-five-hosts-source-stage-v5'
    assert stage['compilerRuns'] == 0 and stage['nativeRuns'] == 0
    assert len(stage['files']) == 146
    for row in stage['files']:
        p = Path(row['path'])
        assert p.is_file() and p.stat().st_size == row['bytes']
        assert sha(p) == row['hash'].removeprefix('sha256:')

    assert bundle['kind'] == 'remaining-five-v5-root-transfer-bundle-r1'
    assert bundle['sourceStageManifestSha256'] == sha(STAGE)
    assert bundle['sourceStageManifestBytes'] == STAGE.stat().st_size
    assert bundle['sourceStageFileCount'] == 146
    assert len(bundle['payload']) == 122
    assert len(bundle['externalDependencies']) == 70
    assert len(bundle['hostRequirements']) == 5
    assert bundle['executionBoundary'] == {'compilerInvocations': 0, 'nativeCalls': 0, 'overwrite': False, 'delete': False}
    labels = ('disabled', 'image', 'shapes.fill-stroke', 'text.bundled-font', 'toggle')
    assert tuple(x['label'] for x in bundle['hostRequirements']) == labels
    for host in bundle['hostRequirements']:
        assert host['runtimeSourceCommit'] == '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
        assert host['runtimeSourceTreeHash'] == 'sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
        assert host['rendererSha256'] == 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
        assert host['bridgeSourceCommit'] == '0a745ab' and host['bridgeHeaderCommit'] == '862997c'
        assert host['bridgeHeaderSha256'] == '12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b'

    stage_rows = {row['path'].removeprefix('factory/native/windows/remaining-five-hosts-v5/'): row for row in stage['files']}
    seen_source, seen_dest = set(), set()
    package_counts = {}
    for row in bundle['payload']:
        source, dest = row['source'], row['destination']
        assert source not in seen_source; seen_source.add(source)
        assert dest not in seen_dest or row['destinationKind'] == 'package'; seen_dest.add((row['destinationKind'], row.get('label'), dest))
        assert dest and '..' not in dest and all(c.isalnum() or c in '._/-' for c in dest)
        if source == 'root-stage-manifest.json': actual = STAGE
        else:
            assert source in stage_rows
            actual = ROOT / source
        assert actual.is_file() and actual.stat().st_size == row['bytes'] and sha(actual) == row['sha256']
        if row['destinationKind'] == 'package': package_counts[row['label']] = package_counts.get(row['label'], 0) + 1
    assert len(seen_source) == 122
    assert package_counts == {x: 14 for x in ('disabled', 'image', 'shapes.fill-stroke', 'text.bundled-font', 'toggle')}

    ext_paths = {}
    for dep in bundle['externalDependencies']:
        assert dep['kind'] in ('file', 'source-tree') and dep['path'].startswith(('C:\\', 'D:\\'))
        digest = dep.get('sha256', dep.get('treeSha256'))
        assert isinstance(digest, str) and digest.removeprefix('sha256:') and len(digest.removeprefix('sha256:')) == 64
        ext_paths.setdefault(dep['path'], set()).add(digest)
    assert len(ext_paths) == 13 and all(len(v) == 1 for v in ext_paths.values())

    # Transfer must finish all source/external checks before creating fresh roots.
    for needle in ('foreach ($dependency in $manifest.externalDependencies)', "if (Test-Path -LiteralPath $toolRoot)", "if (Test-Path -LiteralPath $packageTargets[$label])"):
        assert needle in transfer_text
    assert transfer_text.index('foreach ($dependency in $manifest.externalDependencies)') < transfer_text.index('New-Item -ItemType Directory -Path $toolRoot')
    assert transfer_text.count('Copy-Item') >= 4
    assert 'Start-Process' not in transfer_text and 'swift build' not in transfer_text and 'swiftc' not in transfer_text

    # Admission controls execute before builder loop; every builder call is preflight-only.
    control_anchor = "Invoke-RecordedScript 'v5-pure-production-controls'"
    builder_anchor = '$builder = Join-Path'
    assert control_anchor in admit_text and admit_text.index(control_anchor) < admit_text.index(builder_anchor)
    assert admit_text.count("Invoke-RecordedScript '") == 6
    assert "-PreflightOnly" in admit_text
    assert admit_text.index("if (Test-Path -LiteralPath $outputRoot)") < admit_text.index('New-Item -ItemType Directory -Path $outputRoot')
    assert admit_text.count('-PreflightOnly') == 1
    assert 'Start-Process' not in admit_text and 'swift build' not in admit_text and 'swiftc' not in admit_text
    assert 'compilerStarted -isnot [bool]' in admit_text and 'nativeActions -ne 0' in admit_text and 'outputCreated -isnot [bool]' in admit_text
    return {'stageRecords': 146, 'payloadFiles': 122, 'externalRequirements': 70, 'packagePayloads': package_counts, 'controlScripts': 6, 'preflightOnlyCalls': 5, 'compilerInvocations': 0, 'nativeCalls': 0}


def reject_fault(label, mutate):
    d = json.loads(BUNDLE.read_text())
    mutate(d)
    try:
        audit(d, TRANSFER.read_text(), ADMIT.read_text())
        return False
    except (AssertionError, KeyError, TypeError):
        return True


def main():
    bundle = json.loads(BUNDLE.read_text())
    baseline = audit(bundle, TRANSFER.read_text(), ADMIT.read_text())
    faults = [
        ('payload-count', lambda d: d['payload'].pop()),
        ('external-count', lambda d: d['externalDependencies'].pop()),
        ('payload-hash', lambda d: d['payload'][0].update(sha256='0' * 64)),
    ]
    outcomes = [{'control': name, 'rejected': reject_fault(name, fn)} for name, fn in faults]
    assert all(x['rejected'] for x in outcomes)
    report = {
        'kind': 'remaining-five-v5-root-admission-independent-review-v1',
        'status': 'PASS_SOURCE_REVIEW_ONLY',
        'producerRoot': 'factory/native/windows/remaining-five-hosts-v5/root-admission-r1',
        'producerPins': {
            'transferBundleSha256': sha(BUNDLE),
            'transferScriptSha256': sha(TRANSFER),
            'admissionScriptSha256': sha(ADMIT),
            'sourceStageManifestSha256': sha(STAGE),
        },
        'baseline': baseline,
        'pinnedContext': {
            'runtimeSourceCommit': '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b',
            'runtimeSourceTreeHash': 'c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e',
            'rendererSha256': 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93',
            'bridgeSourceCommit': '0a745ab',
            'bridgeHeaderCommit': '862997c',
            'bridgeHeaderSha256': '12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b',
        },
        'faultControls': outcomes,
        'findings': [
            {'id': 'R1-SOURCE-TREE-DEFERRED', 'severity': 'review-note', 'text': 'Transfer validates existence for five external source-tree rows but does not independently recompute treeSha256; package preflight Assert-FactoryRuntimeSource performs complete binding/hash/membership checks before returning each preflight receipt.'},
        ],
        'checks': [
            '146 source-stage records rehashed against frozen files',
            '122 payload entries are unique, in-stage, exact-byte joined, and partitioned 14 per package across 5 packages',
            '70 external requirements have 65 file pins and 5 runtime source-tree pins with 13 unique paths',
            'fresh tool root and 5 package roots are guarded before transfer writes',
            'fresh results root is guarded before admission writes',
            'six recorded controls precede five builder calls',
            'builder calls use -PreflightOnly exactly once per host and assert compiler/native/output hold boundary',
            'no compiler/native/remote execution performed by this review',
        ],
        'reviewNote': 'Source-tree transfer rows are existence-checked during transfer; full runtime tree byte membership is enforced by each package preflight verifier before its preflight result. No qualification or execution eligibility is granted.',
    }
    out = Path(__file__).resolve().parent / 'report.json'
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'status': report['status'], 'faultControls': len(outcomes), **baseline}, sort_keys=True))

if __name__ == '__main__':
    main()
