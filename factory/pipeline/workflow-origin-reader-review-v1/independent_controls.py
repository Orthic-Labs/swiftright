"""Focused independent wiring controls; actual origin guard, test-only captures."""
from pathlib import Path
from factory.pipeline.test_workflow_origin_reader import WorkflowOriginReaderTests
from factory.pipeline import workflow
from factory.core.artifacts import artifact_ref, write_artifact


def run(mode, reader_mode):
    fixture = WorkflowOriginReaderTests('test_gate_forwards_reader_to_archive_guard')
    fixture.setUp()
    try:
        observed = []
        def callback(*, capture, reference):
            assert capture is fixture.capture
            return fixture.fixture.reader(reference) if reader_mode != 'corrupt' else b'corrupt-archive-bytes'
        args = {} if reader_mode == 'omitted' else {'origin_reader': callback}
        patches = fixture._workflow_patches(observed)
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5]:
            if mode == 'gate':
                result = workflow.gate(fixture.base / 'output', fixture.cases_path, [], fixture.tuple_path,
                                       fixture.config_path, fixture.manifests, test_seed=17, **args)
            else:
                plan = fixture.base / 'prior' / 'gate-results.json'
                plan.parent.mkdir()
                write_artifact(plan, {'seed': 17, 'seedPlan': [{'block': 'block-one',
                    'cases': [artifact_ref(fixture.seeded)], 'commands': []}]})
                write_artifact(plan.parent / 'seed-cases.json', [fixture.seeded])
                result = workflow.gate_evidence(fixture.base / 'output', plan, fixture.cases_path, [],
                    fixture.tuple_path, fixture.config_path, fixture.manifests, **args)
        assert len(observed) == 1
        assert observed[0] is (None if reader_mode == 'omitted' else callback)
        issues = result['gateResults'][0]['issues']
        if reader_mode == 'valid':
            assert issues == [], issues
        elif reader_mode == 'omitted':
            assert issues == ['native origin archive reader unavailable; qualification held'], issues
        else:
            assert issues and all('native origin' in issue for issue in issues), issues
        assert result['status'] == 'blocked' and result['parityGranted'] is False
        return {'entrypoint': mode, 'reader': reader_mode, 'issues': issues, 'callbackIdentityPreserved': True}
    finally:
        fixture.doCleanups()


if __name__ == '__main__':
    import json
    print(json.dumps([run(mode, reader) for mode in ('gate', 'gate_evidence')
                      for reader in ('valid', 'omitted', 'corrupt')], indent=2))
