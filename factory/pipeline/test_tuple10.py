"""Tuple10 candidate isolation tests; fixtures never count as native evidence."""
from pathlib import Path
import tempfile
import unittest

from factory.core.artifacts import file_hash, load_artifact, write_artifact
from factory.pipeline.tuple10 import closure_check, prepare_candidate, staging_pins, validate_host_receipt, finalize_bundle
from factory.pipeline.workflow import ROOT, HERE


class Tuple10Candidates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.staging = ROOT/'docs/sr0-tuple10-staging.md'

    def test_actual_open_status_stays_unbound(self):
        result = closure_check()
        self.assertFalse(result['bound'])
        self.assertTrue(any('CLOSED' in x for x in result['issues']))
        self.assertEqual(len(result['stagedPins']['members']), 8)
        with self.assertRaisesRegex(ValueError, 'explicit CLOSEDtuple10'):
            finalize_bundle(self.base/'bundle', ROOT/'docs/sr0-status.md', self.staging, None, None)
        self.assertFalse((self.base/'bundle').exists())

    def test_full_pins_required(self):
        path = self.base/'staging.md'
        path.write_text(self.staging.read_text().replace('F136046BEFE7EE9900D3466F03D540430E8D84477B8A9089E87497CACEE99F19', 'F136046B'))
        with self.assertRaisesRegex(ValueError, 'exact complete'):
            staging_pins(path)

    def test_stage_pass_or_closed_other_tuple_cannot_close_tuple10(self):
        status = self.base/'status.md'
        for text in ('**Overall: SR0 is OPEN on tuple10.**\nStage PASS, CLOSED historical.', '**Overall: SR0 is CLOSED on tuple08.**'):
            status.write_text(text)
            self.assertFalse(closure_check(status, self.staging)['bound'])

    def test_preclosure_and_staged_runtime_measurements_rejected(self):
        status = self.base/'status.md'
        status.write_text('**Overall: SR0 is CLOSED on tuple10.**')
        closure = {'tuple': '10', 'decision': 'CLOSED', 'statusHash': file_hash(status), 'closedAt': '2026-10-11T02:00:00Z'}
        pins = staging_pins(self.staging)
        measured = {'closureStatusHash': file_hash(status), 'stagingHash': file_hash(self.staging),
                    'stagedPins': pins, 'runtimeCommit': pins['stagedRuntimeCommit'], 'measuredAt': '2026-10-11T01:59:59Z'}
        write_artifact(self.base/'closure.json', closure)
        write_artifact(self.base/'measurements.json', measured)
        result = closure_check(status, self.staging, self.base/'closure.json', self.base/'measurements.json')
        self.assertFalse(result['bound'])
        self.assertTrue(any('after closure' in x for x in result['issues']))
        self.assertTrue(any('own full commit' in x for x in result['issues']))

    def test_synthetic_receipt_rejected(self):
        status = self.base/'status.md'; status.write_text('**Overall: SR0 is CLOSED on tuple10.**')
        write_artifact(self.base/'closure.json', {'synthetic': True})
        write_artifact(self.base/'measurements.json', {'synthetic': True})
        result = closure_check(status, self.staging, self.base/'closure.json', self.base/'measurements.json')
        self.assertIn('synthetic closure/binding evidence rejected', result['issues'])
        self.assertFalse(result['bound'])

    def test_candidate_reproduces81_without_rebinding_history(self):
        protected = [HERE/'inputs/cases.json', HERE/'inputs/observed-tuple.json', HERE/'inputs/acceptance-candidate.json']
        hashes = [file_hash(p) for p in protected]
        output = self.base/'candidate'
        result = prepare_candidate(output)
        self.assertEqual(result['caseDenominator'], 81)
        self.assertEqual(result['baselineSeed'], 0)
        self.assertEqual(sum(result['profileCounts'].values()), 81)
        self.assertFalse(result['acceptedDenominator'])
        self.assertFalse(result['bound'])
        self.assertFalse((output/'observed-tuple-candidate.json').exists())
        config = load_artifact(output/'acceptance-candidate.json')
        self.assertEqual(config['review'], 'pending-maintainer-review')
        self.assertEqual(len(config['baseline']['recipes']), 10)
        self.assertEqual(hashes, [file_hash(p) for p in protected])

    def test_f4_host_source_does_not_embed_tuple_or_case_hash(self):
        from copy import deepcopy
        from factory.probes.generator import generate_probe
        from factory.recipes.recipes import load_recipes
        primary = load_artifact(HERE/'inputs/primary-cases.json')[0]
        case = next(c for c in load_artifact(HERE/'inputs/cases.json') if c['id'] == primary['case'])
        recipe = next(r for r in load_recipes() if r['block'] == case['block'])
        changed = deepcopy(case)
        changed['tuple']['runtimeCommit'] = '2' * 40
        changed['tuple']['hostHashes'] = {'macos': 'sha256:' + '3' * 64, 'windows': 'sha256:' + '4' * 64}
        first = generate_probe(recipe, case, self.base/'before')
        second = generate_probe(recipe, changed, self.base/'after')
        self.assertNotEqual(first['case']['hash'], second['case']['hash'])
        self.assertEqual(first['sourceHash'], second['sourceHash'])
        self.assertEqual((self.base/'before'/first['sourceFile']).read_bytes(), (self.base/'after'/second['sourceFile']).read_bytes())

    def test_host_receipt_nested_binary_hash_is_verified(self):
        runtime = '2' * 40
        closure = {'tuple': '10', 'decision': 'CLOSED', 'statusHash': 'sha256:' + '3' * 64, 'closedAt': '2026-10-11T02:00:00Z'}
        receipt_hash = 'sha256:' + '4' * 64
        source = self.base/'source.swift'; source.write_text('// unit-only source')
        binary = self.base/'host.bin'; binary.write_bytes(b'unit-only bytes')
        path = self.base/'host-measurement.json'
        host = {'platform': 'macos', 'tupleIndependent': True, 'runtimeCommit': runtime,
                'measuredAt': '2026-10-11T02:01:00Z', 'closure': {**closure, 'receiptHash': receipt_hash},
                'source': {'path': source.name, 'hash': file_hash(source)}, 'binary': {'path': binary.name, 'hash': file_hash(binary)}}
        write_artifact(path, host)
        self.assertEqual(set(validate_host_receipt(path, 'macos', runtime, closure, receipt_hash)), {'source', 'binary'})
        binary.write_bytes(b'mutated unit-only bytes')
        with self.assertRaisesRegex(ValueError, 'raw bytes differ'):
            validate_host_receipt(path, 'macos', runtime, closure, receipt_hash)
        host['tupleIndependent'] = False
        write_artifact(path, host)
        with self.assertRaisesRegex(ValueError, 'independent tuple identity'):
            validate_host_receipt(path, 'macos', runtime, closure, receipt_hash)

    def test_windows_receipt_compile_plan_join_cannot_be_forged(self):
        from factory.core.artifacts import canonical_hash
        runtime = '2' * 40
        closure = {'tuple': '10', 'decision': 'CLOSED', 'statusHash': 'sha256:' + '3' * 64, 'closedAt': '2026-10-11T02:00:00Z'}
        receipt_hash = 'sha256:' + '4' * 64
        source = self.base/'main.swift'; source.write_text('// unit-only Windows source')
        binary = self.base/'host.exe'; binary.write_bytes(b'unit-only Windows bytes')
        bindings = [{'path': source.name, 'sha256': file_hash(source)}]
        rp = self.base/'runtime.json'
        write_artifact(rp, {'sourceCommit': runtime, 'sourceBindings': bindings, 'sourceTreeHash': canonical_hash(bindings)})
        pp = self.base/'plan.json'
        write_artifact(pp, {'runtimeSourceCommit': runtime, 'sourceHash': file_hash(source), 'sourceBindings': bindings,
            'runtimeSourceTreeHash': canonical_hash(bindings), 'runtimeSourceReceiptHash': file_hash(rp)})
        op = self.base/'observation.json'
        observation = {'runtimeSourceCommit': runtime, 'exitCode': 0, 'exeSha256': file_hash(binary).removeprefix('sha256:'),
            'runtimeSourceTreeHash': canonical_hash(bindings), 'observedAt': '2026-10-11T02:00:30Z',
            'planSha256': file_hash(pp).removeprefix('sha256:'), 'sourceHash': file_hash(source)}
        write_artifact(op, observation)
        host = {'platform': 'windows', 'tupleIndependent': True, 'runtimeCommit': runtime,
            'measuredAt': '2026-10-11T02:01:00Z', 'closure': {**closure, 'receiptHash': receipt_hash}}
        for key, path in {'source': source, 'binary': binary, 'plan': pp, 'compileObservation': op, 'runtimeSourceReceipt': rp}.items():
            host[key] = {'path': str(path), 'hash': file_hash(path)}
        hp = self.base/'host.json'; write_artifact(hp, host)
        validate_host_receipt(hp, 'windows', runtime, closure, receipt_hash)
        # Outer host stays nonsynthetic; every nested receipt gets independently
        # marked, with all wrapper/plan hashes recomputed to preserve raw joins.
        originals = {path: path.read_bytes() for path in (pp, op, rp)}
        for nested in (pp, op, rp):
            with self.subTest(nested=nested.name):
                value = load_artifact(nested)
                value['synthetic'] = True
                write_artifact(nested, value)
                plan = load_artifact(pp)
                plan['runtimeSourceReceiptHash'] = file_hash(rp)
                write_artifact(pp, plan)
                compiled = load_artifact(op)
                compiled['planSha256'] = file_hash(pp).removeprefix('sha256:')
                write_artifact(op, compiled)
                for key, path in {'plan': pp, 'compileObservation': op, 'runtimeSourceReceipt': rp}.items():
                    host[key]['hash'] = file_hash(path)
                write_artifact(hp, host)
                with self.assertRaisesRegex(ValueError, 'synthetic nested Windows'):
                    validate_host_receipt(hp, 'windows', runtime, closure, receipt_hash)
                for path, payload in originals.items():
                    path.write_bytes(payload)
        for key, path in {'plan': pp, 'compileObservation': op, 'runtimeSourceReceipt': rp}.items():
            host[key]['hash'] = file_hash(path)
        observation['planSha256'] = '5' * 64
        write_artifact(op, observation)
        host['compileObservation']['hash'] = file_hash(op)
        write_artifact(hp, host)
        with self.assertRaisesRegex(ValueError, 'compiled binary/source/runtime'):
            validate_host_receipt(hp, 'windows', runtime, closure, receipt_hash)


if __name__ == '__main__':
    unittest.main()
