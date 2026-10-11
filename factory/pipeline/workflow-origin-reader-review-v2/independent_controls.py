"""Independent CLI/config controls; invented fixture bytes, no native execution."""
import contextlib
import io
import json
import tempfile
from pathlib import Path
from factory.pipeline import workflow
from factory.pipeline.__main__ import main
from factory.pipeline.reader_config import load_origin_reader_config
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.pipeline.test_workflow_origin_reader import WorkflowOriginReaderTests
from factory.core.artifacts import canonical_hash, artifact_ref, write_artifact


def runtime(mode, configured):
    fixture = WorkflowOriginReaderTests('test_gate_forwards_reader_to_archive_guard')
    fixture.setUp()
    try:
        archive = fixture.base / 'archive'; archive.mkdir()
        raw = fixture.fixture
        entries = {name + '.raw': data for name, data in raw.raw.items()}
        entries.update({'host/' + name: data for name, data in raw.host.items()})
        entries.update({'runtime/' + name: data for name, data in raw.runtime.items()})
        entries['tool/compiler.bin'] = raw.compiler
        for name, data in entries.items():
            path = archive / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        cfg = fixture.base / 'reader.json'
        cfg.write_text(json.dumps({'version': 1, 'macRoots': [], 'windowsArchives': {
            canonical_hash(fixture.capture).removeprefix('sha256:'): 'archive'}, 'macPathMap': {}}))
        seen = []
        patches = fixture._workflow_patches(seen)
        argv = [mode, '--output', str(fixture.base / 'output'), '--cases', str(fixture.cases_path),
                '--tuple', str(fixture.tuple_path), '--config', str(fixture.config_path),
                '--manifests', str(fixture.manifests), '--evidence-root', str(fixture.base)]
        if mode == 'gate':
            argv += ['--test-seed', '17']
        else:
            plan = fixture.base / 'prior' / 'gate-results.json'; plan.parent.mkdir()
            write_artifact(plan, {'seed': 17, 'seedPlan': [{'block': 'block-one',
                'cases': [artifact_ref(fixture.seeded)], 'commands': []}]})
            write_artifact(plan.parent / 'seed-cases.json', [fixture.seeded])
            argv += ['--plan', str(plan)]
        if configured:
            argv += ['--origin-reader-config', str(cfg)]
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], contextlib.redirect_stdout(io.StringIO()):
            status = main(argv)
        assert status == 3 and len(seen) == 1
        result = json.loads((fixture.base / 'output' / 'gate-results.json').read_text())
        issues = result['gateResults'][0]['issues']
        if configured:
            assert isinstance(seen[0], ArchiveByteReader)
            assert issues == [], issues
        else:
            assert seen[0] is None
            assert issues == ['native origin archive reader unavailable; qualification held'], issues
        assert result['parityGranted'] is False and result['status'] == 'blocked'
        return {'mode': mode, 'configured': configured, 'exitCode': status, 'originIssues': issues}
    finally:
        fixture.doCleanups()


def config_faults():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); (root / 'mac').mkdir(); (root / 'mac' / 'tool').write_bytes(b'fixture')
        good = {'version': 1, 'macRoots': ['mac'], 'windowsArchives': {}, 'macPathMap': {}}
        rows = []
        values = {
            'bool-version': {'version': True}, 'float-version': {'version': 1.0},
            'null-roots': {'macRoots': None}, 'numeric-root': {'macRoots': [1]},
            'duplicate-root': {'macRoots': ['mac','mac']}, 'alias-root-duplicate': {'macRoots': ['mac','./mac']},
            'file-root': {'macRoots': ['mac/tool']}, 'absolute-root': {'macRoots': [str(root/'mac')]},
            'windows-list': {'windowsArchives': []}, 'numeric-windows-location': {'windowsArchives': {'a'*64: 1}},
            'uppercase-windows-key': {'windowsArchives': {'A'*64: 'mac'}},
            'logical-dotdot': {'macPathMap': {'/x/../tool': 'mac/tool'}},
            'logical-nonnormal': {'macPathMap': {'/x//tool': 'mac/tool'}},
            'map-directory': {'macPathMap': {'/x/tool': 'mac'}},
            'extra-field': {'unknown': True},
        }
        cfg = root / 'config.json'
        for mode, changes in values.items():
            cfg.write_text(json.dumps(good | changes)); rejected = False
            try: load_origin_reader_config(cfg)
            except (OSError, ValueError, TypeError): rejected = True
            assert rejected, mode
            rows.append({'mode': mode, 'rejected': True})
        cfg.write_text('{"version":1,"macRoots":["mac"],"windowsArchives":{},"macPathMap":{"/x":"mac/tool","/x":"mac/tool"}}')
        try: load_origin_reader_config(cfg)
        except ValueError: rows.append({'mode':'nested-duplicate-json-key','rejected':True})
        else: raise AssertionError('nested duplicate accepted')
        return rows


if __name__ == '__main__':
    print(json.dumps({'runtime': [runtime(mode, configured) for mode in ('gate','gate-evidence')
                                 for configured in (True, False)], 'configFaults': config_faults()}, indent=2))
