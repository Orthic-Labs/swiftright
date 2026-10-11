"""Read-only two-source-level Mac100 join; compiler process origin stays unavailable."""
from pathlib import Path
import argparse
import hashlib
import json

BLOCKS = ('stack-overlay', 'custom-layout', 'padding-frame', 'preference-key', 'scroll-view')
SEED = 14577611000270672472


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def canonical_hash(value):
    return digest(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def exact_int(value):
    return type(value) is int


def verify(mac_root, lineage_root, plans_root, read_bytes=None):
    mac_root, lineage_root, plans_root = map(Path, (mac_root, lineage_root, plans_root))
    read = read_bytes or (lambda path: Path(path).read_bytes())
    consumed = {}

    def raw(path):
        data = read(path)
        require(type(data) is bytes, 'reader must return exact bytes')
        consumed[str(path)] = digest(data)
        return data

    def load(path):
        return json.loads(raw(path))

    def archived(root, relative):
        relative = Path(relative)
        require(not relative.is_absolute() and '..' not in relative.parts, 'archive path escape')
        return root / relative

    def pinned(root, descriptor, key='ownedPath'):
        data = raw(archived(root, descriptor[key]))
        require(digest(data) == descriptor['sha256'], 'archive raw hash drift')
        require(exact_int(descriptor['bytes']) and len(data) == descriptor['bytes'], 'archive byte count drift')
        return data

    pins_doc = load(mac_root / 'input-pins.json')
    require(pins_doc['seed'] == SEED and exact_int(pins_doc['seed']), 'seed')
    pins = pins_doc['rows']
    require(len(pins) == 5 and len({row['block'] for row in pins}) == 5 and {row['block'] for row in pins} == set(BLOCKS), 'exact five input cases')
    pins = {row['block']: row for row in pins}
    top = load(lineage_root / 'lineage.json')
    require(top['seed'] == SEED and exact_int(top['seed']), 'lineage seed')
    require(len(top['cases']) == 5 and len({row['block'] for row in top['cases']}) == 5 and {row['block'] for row in top['cases']} == set(BLOCKS), 'exact five lineage cases')
    top_cases = {row['block']: row for row in top['cases']}
    policy = load(lineage_root / 'policy/source-policy.json')
    script = raw(lineage_root / policy['scriptPath'])
    require(digest(script) == policy['scriptSha256'], 'capture policy bytes')
    adapter = pinned(lineage_root, policy['adapterSource'], 'path')
    for field in ('argvRecorded', 'pidRecorded', 'startedAtRecorded', 'endedAtRecorded', 'returnCodeRecorded'):
        require(policy['actualProcessReceipt'][field] is False, 'compiler origin falsely promoted')
    cases = []
    for block in BLOCKS:
        plan_path = plans_root / block / 'package/plan.json'
        plan = load(plan_path)
        require(exact_int(plan['seed']) and plan['seed'] == SEED, 'plan seed')
        require(plan['executionEligible'] is False and plan['seedCaptureSourceMatched'] is False, 'frozen plan flags')
        window_witness = raw(plans_root / block / 'package/Sources/FactoryProbe/Witness.swift')
        lineage = load(lineage_root / 'cases' / block / 'lineage.json')
        require(lineage == top_cases[block], 'top/case lineage drift')
        require(lineage['compileProcessProof'].startswith('MISSING:'), 'compile origin boundary')
        pin = pins[block]
        witness = pinned(lineage_root, lineage['sourceWitness'])
        input_witness = pinned(mac_root, pin['source'], 'path')
        manifest_raw = pinned(mac_root, pin['manifest'], 'path')
        manifest = json.loads(manifest_raw)
        require(digest(manifest_raw) == plan['manifestHash'], 'plan manifest join')
        require(lineage['sourceWitness']['expectedInputPath'] == pin['source']['path'] and lineage['sourceWitness']['expectedInputSha256'] == digest(input_witness), 'Witness input mapping')
        require(witness == window_witness == input_witness, 'exact Witness byte mismatch')
        require(digest(witness) == plan['sourceHash'] == manifest['sourceHash'] == lineage['sourceWitness']['summarySourceHash'] == pin['source']['declared'], 'Witness source levels')
        require(plan['case'] == manifest['case'] == {'id': lineage['caseID'], 'hash': lineage['caseHash']}, 'case/source mapping')
        require(manifest['witnessType'].startswith('Witness_'), 'witness type')
        adapted = pinned(lineage_root, lineage['adaptedCaptureHost'])
        require(adapted == adapter.replace(b'__WITNESS_TYPE__', manifest['witnessType'].encode()), 'exact generated adapter substitution')
        require(digest(adapted) == lineage['adaptedCaptureHost']['summaryCompiledAdapterHash'], 'adapter source level')
        summary_path = mac_root / 'evidence' / plan['case']['id'] / 'summary.json'
        summary = load(summary_path)
        require(summary['case'] == plan['case'] and summary['sourceHash'] == digest(witness) and summary['compiledAdapterHash'] == digest(adapted) and summary['adapterSourceHash'] == digest(adapter), 'actual summary source joins')
        require(summary['status'] == 'CANDIDATE_CAPTURED' and summary['candidateOnly'] is True and summary['acceptance'] == 'not-promoted', 'candidate boundary')
        binary = raw(archived(mac_root, lineage['binary']['v1OwnedPath']))
        require(digest(binary) == lineage['binary']['sha256'] == summary['binaryHash'] == lineage['binary']['summaryBinaryHash'], 'binary raw join')
        require(exact_int(lineage['binary']['bytes']) and len(binary) == lineage['binary']['bytes'], 'binary size')
        for key in ('stdoutPath', 'stderrPath'):
            require(digest(raw(archived(lineage_root, lineage['buildOutput'][key]))) == lineage['buildOutput'][key.replace('Path', 'Sha256')], 'build raw output')
        joins = lineage['rawInstrumentedJoins']
        rows = summary['runs']
        for collection in (joins, rows):
            require(len(collection) == 20 and all(exact_int(row['run']) for row in collection) and {row['run'] for row in collection} == set(range(1, 21)), 'exact twenty integer unique runs')
        rows = {row['run']: row for row in rows}
        observations = []
        for join in joins:
            index = join['run']
            run_root = summary_path.parent / f'run-{index:03d}'
            expected_raw = run_root / 'instrumented.raw.json'
            require(mac_root / join['rawPath'] == expected_raw and mac_root / join['rawSummaryPath'] == summary_path, 'raw path/run mapping')
            observation_raw = raw(expected_raw)
            observation_hash = digest(observation_raw)
            require(observation_hash == join['rawSha256'] == join['summaryInstrumentedRawHash'] == rows[index]['instrumented']['rawHash'], 'raw observation hash joins')
            observation = json.loads(observation_raw)
            require(observation.get('status') in ('OBSERVED', 'UNOBSERVED') and observation.get('instrumented') is True, 'raw observation failed')
            require(exact_int(observation.get('monoStartNs')) and exact_int(observation.get('monoEndNs')) and 0 <= observation['monoStartNs'] < observation['monoEndNs'], 'raw timing failure')
            capture_path = run_root / 'capture.json'
            capture = load(capture_path)
            require(capture['case'] == plan['case'] and exact_int(capture['meta']['run']) and capture['meta']['run'] == index, 'capture case/run')
            require(capture['provenance']['sourceHash'] == observation_hash, 'capture raw observation provenance')
            binaries = [item for item in capture['provenance']['inputs'] if item['id'] == 'macos.capture.binary']
            require(len(binaries) == 1 and binaries[0]['hash'] == digest(binary), 'capture binary lineage')
            clock = load(run_root / 'clock.json')
            require(exact_int(clock['startNs']) and exact_int(clock['endNs']) and 0 <= clock['startNs'] < clock['endNs'], 'capture timing failure')
            require(clock['startNs'] == observation['monoStartNs'] and clock['endNs'] == observation['monoEndNs'], 'raw/clock timing join')
            require(capture['meta']['clock']['correlationHash'] == canonical_hash(clock), 'capture clock hash')
            require(capture['meta']['conditions']['candidateOnly'] is True and capture['meta']['conditions']['observationalOnly'] is True, 'capture candidate scope')
            observations.append({'run': index, 'captureHash': consumed[str(capture_path)], 'rawHash': observation_hash, 'rawStatus': observation['status']})
        cases.append({'block': block, 'case': plan['case'], 'planHash': consumed[str(plan_path)], 'witnessHash': digest(witness), 'adaptedHostHash': digest(adapted), 'binaryHash': digest(binary), 'runs': observations})
    return {'kind': 'seed-mac100-two-source-level-join-v2', 'sourceReplayEligible': True,
            'cases': cases, 'consumed': consumed, 'witnessSourceScope': 'exact Mac/Windows Witness.swift bytes',
            'captureSourceScope': 'exact instrumented.raw.json bytes; no alias to witness',
            'compilerProcessOrigin': 'MISSING; qualified origin held', 'windowsCompileRequiredBeforeNative': True,
            'windowsCompileValidated': False, 'nativeParity': 'hold', 'frozenPlansModified': False}


def main():
    parser = argparse.ArgumentParser()
    for name in ('mac-root', 'lineage-root', 'plans-root', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    require(not args.output.exists(), 'fresh output required')
    result = verify(args.mac_root, args.lineage_root, args.plans_root)
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
