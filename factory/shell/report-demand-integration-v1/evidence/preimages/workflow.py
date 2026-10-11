"""Measured preparation, strict collection & held gate orchestration."""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
import secrets
import shlex

from factory.core.artifacts import artifact_ref, canonical_hash, file_hash, load_artifact, write_artifact
from factory.recipes.recipes import load_recipes
from factory.recipes.cases import expand_cases, validate_case_manifest
from factory.probes.generator import generate_probe

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def fresh_output(path):
    out = Path(path).resolve()
    protected = [HERE / name for name in ('inputs', 'cases', 'manifests', 'probes')]
    if any(out == p or p in out.parents or out in p.parents for p in protected):
        raise ValueError('output overlaps protected current batch')
    if out.exists() and any(out.iterdir()):
        raise ValueError('output must be fresh & empty')
    out.mkdir(parents=True, exist_ok=True)
    return out


def prepare(output, tuple_path, config_path, seed=0, snapshot_created_at=None):
    tuple_value, config = load_artifact(tuple_path), load_artifact(config_path)
    if canonical_hash(config) != tuple_value.get('acceptanceConfigHash'):
        raise ValueError('acceptance config does not bind measured tuple')
    baseline = config.get('baseline')
    if baseline is not None:
        entries = baseline.get('recipes', []) if isinstance(baseline, dict) else []
        if not isinstance(entries, list) or not entries or any(not isinstance(entry, dict) or entry.get('seed') != seed for entry in entries):
            raise ValueError('prepare seed differs from bound baseline seed')
    out = fresh_output(output)
    cases, probes, manifests = [], [], []
    for recipe in load_recipes():
        expansion = expand_cases(recipe, tuple_value, seed=seed, snapshot_created_at=snapshot_created_at)
        validate_case_manifest(expansion)
        write_artifact(out / 'manifests' / (recipe['block'] + '.json'), expansion['manifest'])
        manifests.append(expansion['manifest'])
        for case in expansion['cases']:
            write_artifact(out / 'cases' / (case['id'].replace('/', '--') + '.json'), case)
            probes.append(generate_probe(recipe, case, out / 'probes'))
            cases.append(case)
    write_artifact(out / 'cases.json', cases)
    write_artifact(out / 'probe-manifests.json', probes)
    write_artifact(out / 'observed-tuple.json', tuple_value)
    write_artifact(out / 'acceptance-candidate.json', config)
    summary = {'caseDenominator': len(cases), 'blocks': len(manifests), 'tupleHash': canonical_hash(tuple_value), 'seed': seed,
               'mode': 'candidate-preparation', 'acceptedDenominator': False}
    write_artifact(out / 'prepare-summary.json', summary)
    return summary


def synthetic(value):
    if isinstance(value, dict):
        if value.get('synthetic') is True or value.get('specExample') is True:
            return True
        return any(synthetic(v) for v in value.values())
    if isinstance(value, list):
        return any(synthetic(v) for v in value)
    return isinstance(value, str) and any(s in value.lower() for s in ('synthetic', 'spec-example', 'test-fixture'))


def validate_batch(value, cases):
    validate_case_manifest(value if 'manifest' in value else {'manifest': value}, cases)


def load_raw_json(path):
    """Native raw measurements allow floats; duplicate keys/constants do not."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate key in raw native JSON')
            result[key] = value
        return result
    def constant(_):
        raise ValueError('non-finite constant in raw native JSON')
    return json.loads(Path(path).read_text(encoding='utf-8-sig'), object_pairs_hook=pairs, parse_constant=constant)


def validate_windows_archive(capture, directory):
    """Bind normalized Windows capture to adjacent owned source & raw receipt."""
    directory = Path(directory).resolve()
    plan = load_artifact(directory / 'plan.json')
    source_hash = file_hash(directory / 'Witness.swift')
    conditions = capture['meta']['conditions']
    if (plan.get('case') != capture['case'] or plan.get('sourceHash') != source_hash
            or capture['provenance']['sourceHash'] != source_hash
            or conditions.get('actualSourceHash') != source_hash):
        raise ValueError('Windows source/plan/case binding mismatch')
    if (conditions.get('rawWitnessHash') != source_hash
            or conditions.get('rawPlanHash') != file_hash(directory / 'plan.json')
            or load_artifact(directory / 'tuple.json') != capture['tuple']):
        raise ValueError('Windows raw witness/plan/tuple archive binding mismatch')
    receipt_path = directory / 'native-observation.json'
    receipt_hash = file_hash(receipt_path)
    if (conditions.get('rawReceiptHash') != receipt_hash
            or capture['meta']['clock']['correlationHash'] != receipt_hash):
        raise ValueError('Windows raw receipt/clock archive hash mismatch')
    receipts = load_raw_json(receipt_path)
    if not isinstance(receipts, list):
        raise ValueError('Windows raw receipt must retain original observation array')
    matching = [r for r in receipts if r.get('index') == capture['meta']['run']]
    if len(matching) != 1:
        raise ValueError('Windows receipt run missing or duplicated')
    row = matching[0]
    if (row.get('case') != capture['case'] or row.get('sourceHash') != source_hash
            or 'sha256:' + row.get('exeSha256', '') != capture['meta']['host']['hash']
            or 'sha256:' + row.get('exeSha256', '') != conditions.get('actualHostExecutableHash')
            or 'sha256:' + row.get('rendererSha256', '') != conditions.get('actualRendererHash')
            or conditions.get('actualRendererHash') != capture['tuple']['rendererHash']
            or conditions.get('tupleWindowsHostHash') != capture['tuple']['hostHashes']['windows']
            or row.get('hostValid') is not True or row.get('exitCode') != 0):
        raise ValueError('Windows raw receipt case/source/host/renderer binding mismatch')
    for key in ('nativeParity', 'occlusionQualified'):
        if conditions.get(key) != row.get(key):
            raise ValueError('Windows native qualification differs from raw receipt')
    bindings = row.get('files')
    if not isinstance(bindings, list) or not bindings:
        raise ValueError('Windows raw receipt file bindings missing')
    paths = set()
    for binding in bindings:
        relative = binding.get('path')
        if not isinstance(relative, str):
            raise ValueError('Windows raw receipt file path invalid')
        # Raw Windows receipts may use native separators; resolve only here.
        path = (directory / relative.replace('\\', '/')).resolve()
        if path == directory or directory not in path.parents or path in paths:
            raise ValueError('Windows raw receipt file escapes archive or repeats')
        paths.add(path)
        if file_hash(path) != 'sha256:' + binding.get('sha256', ''):
            raise ValueError('Windows raw receipt file hash mismatch')
    required = {directory / 'native.uia.json', directory / 'native.screen.png', directory / 'host.stdout.txt'}
    if not required.issubset(paths):
        raise ValueError('Windows raw receipt missing UIA/screen/host file bindings')
    if conditions.get('rawUIAHash') != file_hash(directory / 'native.uia.json'):
        raise ValueError('Windows raw UIA archive hash mismatch')


def collect(cases, evidence_roots, exclude_capture_dirs=None):
    """Only explicit roots; duplicates, stale bindings & synthetic captures rejected."""
    from factory.tools.schema_validate import load_registry, validate_artifact
    registry, schemas = load_registry(ROOT / 'factory/spec/schema')
    by_id = {case['id']: case for case in cases}
    if len(by_id) != len(cases):
        raise ValueError('duplicate case IDs')
    roots = [Path(p).resolve() for p in evidence_roots]
    excluded = [Path(p).resolve() for p in (exclude_capture_dirs or [])]
    if len(set(roots)) != len(roots) or any(a != b and a in b.parents for a in roots for b in roots):
        raise ValueError('evidence roots overlap or repeat')
    if any(not p.is_dir() or not any(root in p.parents for root in roots) for p in excluded):
        raise ValueError('superseded directory must exist inside explicitly selected evidence root')
    captures, archives, diagnostics, superseded, seen = [], [], [], [], set()
    for root in roots:
        if not root.is_dir():
            diagnostics.append({'path': str(root), 'reason': 'selected evidence root missing'})
            continue
        for path in sorted(root.rglob('capture.json')):
            record = {'path': str(path), 'hash': file_hash(path)}
            try:
                value = load_artifact(path)
                if any(p == path.parent or p in path.parents for p in excluded):
                    superseded.append({**record, 'capture': artifact_ref(value), 'case': value.get('case'), 'reason': 'explicitly superseded capture directory'})
                    continue
                case = by_id.get(value.get('case', {}).get('id'))
                cid = value.get('id')
                if cid in seen:
                    raise ValueError('repeated capture ID')
                seen.add(cid)
                if synthetic(value):
                    raise ValueError('synthetic capture rejected')
                errors = validate_artifact(value, registry, schemas)
                if errors:
                    raise ValueError('schema invalid: ' + '; '.join(errors))
                if not case or value['case'] != artifact_ref(case):
                    raise ValueError('stale or unknown case ref')
                if value.get('tuple') != case['tuple']:
                    raise ValueError('stale tuple')
                if value.get('platform') not in ('macos', 'windows'):
                    raise ValueError('native platform required')
                files = [dict(path=str(p), hash=file_hash(p)) for p in sorted(path.parent.iterdir()) if p.is_file()]
                image_hashes = {f['hash'] for f in files if Path(f['path']).suffix.lower() == '.png'}
                if any(im['hash'] not in image_hashes for im in value.get('images', [])):
                    raise ValueError('image hash lacks matching raw PNG archive')
                if value['platform'] == 'macos':
                    if file_hash(path.parent / 'instrumented.raw.json') != value['provenance']['sourceHash']:
                        raise ValueError('provenance raw source hash mismatch')
                    if canonical_hash(load_artifact(path.parent / 'clock.json')) != value['meta']['clock']['correlationHash']:
                        raise ValueError('clock correlation archive hash mismatch')
                else:
                    validate_windows_archive(value, path.parent)
                archive = {**record, 'capture': artifact_ref(value), 'case': value['case'], 'platform': value['platform'], 'files': files}
                summary_path = path.parent.parent / 'summary.json'
                if value['platform'] == 'macos' and summary_path.exists():
                    summary = load_raw_json(summary_path)
                    if summary.get('case') != value['case'] or summary.get('sourceHash') != summary.get('probeManifest', {}).get('sourceHash'):
                        raise ValueError('Mac source summary case/manifest binding mismatch')
                    if {'id': 'macos.capture.binary', 'hash': summary.get('binaryHash')} not in value['provenance'].get('inputs', []):
                        raise ValueError('Mac executed binary differs from source summary')
                    archive['sourceSummary'] = {'path': str(summary_path), 'hash': file_hash(summary_path)}
                    archive['sourceHash'] = summary['sourceHash']
                captures.append(value)
                archives.append(archive)
            except (OSError, ValueError, TypeError, KeyError) as exc:
                diagnostics.append({**record, 'reason': str(exc)})
    return {'captures': captures, 'archives': archives, 'diagnostics': diagnostics, 'supersededArchives': superseded,
            'selectedRoots': [str(p) for p in roots], 'excludedCaptureDirectories': [str(p) for p in excluded]}


def validate_primary_source(case, lineage, captures, mac_archives, superseded):
    expected_source_hash = lineage[-1]['sourceHash']
    if any(a.get('sourceHash') != expected_source_hash for a in mac_archives):
        raise ValueError('selected Mac primary source differs from current source lineage')
    if superseded:
        replacement = [c for c in captures if c['platform'] == 'macos']
        if (any(a['case'] != artifact_ref(case) for a in superseded)
                or len(replacement) != 20
                or {c['meta']['run'] for c in replacement} != set(range(1, 21))):
            raise ValueError('superseded primary source lacks complete20 canonical replacement captures')


def report(output, cases_path, roots, primary_path, config_path, registry_path, demand_path, compile_path=None, corrections_dir=None, native_holds_path=None, exclude_capture_dirs=None):
    from factory.comparison import compare_case
    from factory.reports.report import build_report
    cases = load_artifact(cases_path)
    collected = collect(cases, roots, exclude_capture_dirs)
    config = load_artifact(config_path)
    out = fresh_output(output)
    verdicts = [compare_case(case, [c for c in collected['captures'] if c['case']['id'] == case['id']], acceptance_config=config) for case in cases]
    write_artifact(out / 'captures.json', collected['captures'])
    write_artifact(out / 'verdicts.json', verdicts)
    write_artifact(out / 'collection.json', {k: v for k, v in collected.items() if k != 'captures'})
    paths = build_report(load_artifact(registry_path), cases, collected['captures'], verdicts, out / 'report', load_artifact(demand_path))
    compile_value = load_artifact(compile_path) if compile_path else {}
    compile_by_block = {v['block']: v for v in compile_value.get('records', [])}
    native_holds = load_artifact(native_holds_path) if native_holds_path else {}
    native_by_block = {v['block']: v for v in native_holds.get('rows', [])}
    primaries = []
    for primary in load_artifact(primary_path):
        case = next(c for c in cases if c['id'] == primary['case'])
        original_path = Path(primary['manifestPath'])
        original = load_artifact(original_path)
        if original['case'] != artifact_ref(case) or file_hash(original_path.parent / original['sourceFile']) != original['sourceHash']:
            raise ValueError('primary manifest has stale case binding')
        lineage = [{'manifest': str(original_path), 'manifestHash': file_hash(original_path), 'sourceHash': original['sourceHash'], 'status': 'original'}]
        if corrections_dir:
            correction_path = Path(corrections_dir) / original_path.name
            if correction_path.exists():
                correction = load_artifact(correction_path)
                if correction['case'] != artifact_ref(case) or file_hash(correction_path.parent / correction['sourceFile']) != correction['sourceHash']:
                    raise ValueError('corrected source lineage binding invalid')
                lineage[0]['status'] = 'superseded-source-observation-only'
                lineage.append({'manifest': str(correction_path.resolve()), 'manifestHash': file_hash(correction_path), 'sourceHash': correction['sourceHash'], 'status': 'corrected-current'})
        compile_record = compile_by_block.get(primary['block'], {'compileStatus': 'not-observed'})
        if compile_record.get('compileStatus') != 'not-observed':
            if (compile_record.get('case') != artifact_ref(case)
                or compile_record.get('sourceHash') not in {v['sourceHash'] for v in lineage}
                or compile_record.get('actualSourceHash') != compile_record.get('sourceHash')
                or compile_value.get('observedTupleHash') != canonical_hash(case['tuple'])):
                raise ValueError('compile evidence does not bind primary case/source/tuple')
            stderr = compile_record.get('stderr', {})
            stderr_path = Path(stderr.get('path', ''))
            if not stderr_path.is_absolute():
                stderr_path = ROOT / stderr_path
            if file_hash(stderr_path) != stderr.get('hash'):
                raise ValueError('compile stderr archive hash mismatch')
        selected = [c for c in collected['captures'] if c['case']['id'] == primary['case']]
        mac_archives = [a for a in collected['archives'] if a['case']['id'] == primary['case'] and a['platform'] == 'macos']
        superseded = [a for a in collected['supersededArchives'] if a.get('case', {}).get('id') == primary['case']]
        validate_primary_source(case, lineage, selected, mac_archives, superseded)
        native_hold = native_by_block.get(primary['block'])
        if native_hold and (native_hold['case'] != artifact_ref(case) or native_holds.get('observedTupleHash') != canonical_hash(case['tuple']) or native_hold.get('sourceHash') not in {v['sourceHash'] for v in lineage}):
            raise ValueError('native hold does not bind primary case/source/tuple')
        primaries.append({**primary, 'nativeCaptureCounts': dict(Counter(c['platform'] for c in selected)),
                          'archives': [v for v in collected['archives'] if v['case']['id'] == primary['case']],
                          'windowsCompile': compile_record, 'windowsNativeHold': native_hold, 'sourceLineage': lineage,
                          'macCapturedSourceHashes': sorted({a['sourceHash'] for a in mac_archives}),
                          'qualification': 'unqualified', 'parity': 'held'})
    summary = {'kind': 'pipeline-pilot-summary', 'caseDenominator': len(cases), 'primaryDenominator': len(primaries),
               'nativeCaptureCount': len(collected['captures']), 'verdictCounts': dict(Counter(v.get('status', 'blocked') for v in verdicts)),
               'diagnostics': collected['diagnostics'], 'selectedRoots': collected['selectedRoots'], 'primaries': primaries,
               'supersededArchives': collected['supersededArchives'], 'excludedCaptureDirectories': collected['excludedCaptureDirectories'],
               'reports': paths, 'role': 'Alchemist bounded transformation', 'parityGranted': False,
               'compileSummary': {'path': str(Path(compile_path).resolve()), 'hash': file_hash(compile_path)} if compile_path else None,
               'windowsNativeHolds': {'path': str(Path(native_holds_path).resolve()), 'hash': file_hash(native_holds_path)} if native_holds_path else None}
    write_artifact(out / 'pilot-summary.json', summary)
    rows = ['# Actual pilot evidence', '', f"Fixed denominator: {len(cases)} cases; {len(primaries)} primaries. Native captures: {len(collected['captures'])}. Parity held.", '', '| Block | Mac | Windows | Windows compile | Qualification |', '|---|---:|---:|---|---|']
    for p in primaries:
        counts = p['nativeCaptureCounts']
        rows.append(f"| {p['block']} | {counts.get('macos', 0)} | {counts.get('windows', 0)} | {p['windowsCompile'].get('compileStatus')} | unqualified |")
    rows += ['', 'Raw capture archives: [collection.json](collection.json). Full diagnostics & compile refs: [pilot-summary.json](pilot-summary.json).']
    if native_holds:
        rows += ['', f"Windows actual native replay count: {native_holds.get('nativeRuns', 0)}.", '']
        rows += [f"- {p['block']}: {p['windowsNativeHold']['reason']}" for p in primaries if p['windowsNativeHold']]
    rows += ['', 'Plain/offscreen/compositor/background captures remain unqualified. F10 requires fresh seeded captures, repeat qualification, Windows replay, trusted callbacks & SR0 closure.']
    (out / 'PILOT.md').write_text('\n'.join(rows) + '\n')
    return summary


def gate(output, cases_path, roots, tuple_path, config_path, manifests_dir, test_seed=None):
    from factory.gate.core import evaluate_gate, expand_gate_seeded_cases
    out = fresh_output(output)
    cases, tuple_value, config = load_artifact(cases_path), load_artifact(tuple_path), load_artifact(config_path)
    collected = collect(cases, roots)
    seed = secrets.randbits(64) if test_seed is None else test_seed
    reports, plan, seeded_all = [], [], []
    for recipe in load_recipes():
        selected = [c for c in cases if c['block'] == recipe['block']]
        manifest = load_artifact(Path(manifests_dir) / (recipe['block'] + '.json'))
        validate_batch(manifest, selected)
        seeded = expand_gate_seeded_cases(recipe, tuple_value, seed)
        seeded_all.extend(seeded)
        commands = []
        for case in seeded:
            write_artifact(out / 'seed-cases' / (case['id'].replace('/', '--') + '.json'), case)
            generate_probe(recipe, case, out / 'seed-probes')
            # Locate generated manifest by its exact case binding, never reuse baseline.
            candidates = [p for p in (out / 'seed-probes').glob('*.manifest.json') if load_artifact(p).get('case', {}).get('id') == case['id']]
            if len(candidates) != 1:
                raise ValueError('seed probe manifest binding unavailable')
            manifest_path = candidates[0]
            commands.append({'case': artifact_ref(case), 'manifest': str(manifest_path), 'manifestHash': file_hash(manifest_path),
                'macCapture': 'python3 -m factory.native.macos.capture --manifest ' + shlex.quote(str(manifest_path)) + ' --runs 20 --output ' + shlex.quote(str(out / 'seed-native-macos' / recipe['block'])),
                'windowsBuild': 'python3 -m factory.native.windows.adapter ' + shlex.quote(str(manifest_path)) + ' --renderer --output ' + shlex.quote(str(out / 'seed-native-windows' / recipe['block'])),
                'windowsReplay': 'held: requires desktop-coordinated native runner', 'executionStatus': 'pipeline-held'})
        result = evaluate_gate(recipe=recipe, cases=selected, captures=[c for c in collected['captures'] if c['case']['id'] in {x['id'] for x in selected}], tuple_value=tuple_value,
                               acceptance_config=config, normalizer_rules=config.get('normalizers', []), expected_cases=selected, seed=seed,
                               random_case_factory=lambda _, frozen=seeded: frozen)
        reports.append(result)
        plan.append({'block': recipe['block'], 'seed': seed, 'cases': [artifact_ref(c) for c in seeded], 'commands': commands})
    value = {'seed': seed, 'seedOrigin': 'explicit-tests-only' if test_seed is not None else 'runtime-secrets.randbits', 'status': 'blocked',
             'parityGranted': False, 'gateResults': reports, 'seedPlan': plan, 'collectionDiagnostics': collected['diagnostics']}
    write_artifact(out / 'gate-results.json', value)
    write_artifact(out / 'seed-cases.json', seeded_all)
    return value


def queue(output, registry_path):
    from factory.queue.store import QueueStore, BlockedError
    out = fresh_output(output)
    registry = load_artifact(registry_path)
    store = QueueStore(out / 'queue-state.json', registry_path)
    outcomes = []
    for block in registry['blocks']:
        try:
            ticket = store.enqueue(block['id'])
            outcomes.append({'block': block['id'], 'ticket': ticket['id'], 'status': 'staged'})
        except BlockedError as exc:
            outcomes.append({'block': block['id'], 'status': 'dependency-held', 'reason': str(exc)})
    summary = {'activation': store.ACTIVATION, 'mode': store.MODE, 'outcomes': outcomes, 'contributorActivation': 'held-until-plan-round-3-exit'}
    write_artifact(out / 'queue-summary.json', summary)
    return summary


def gate_evidence(output, plan_path, cases_path, roots, tuple_path, config_path, manifests_dir, exclude_capture_dirs=None):
    """Reevaluate one recorded seed batch with its own archived captures."""
    from factory.gate.core import evaluate_gate, expand_gate_seeded_cases
    plan = load_artifact(plan_path)
    seed = plan['seed']
    cases, tuple_value, config = load_artifact(cases_path), load_artifact(tuple_path), load_artifact(config_path)
    recipes = load_recipes()
    seed_cases = load_artifact(Path(plan_path).parent / 'seed-cases.json')
    expected = {p['block']: p['cases'] for p in plan['seedPlan']}
    for recipe in recipes:
        seeded = [c for c in seed_cases if c['block'] == recipe['block']]
        if expected.get(recipe['block']) != [artifact_ref(c) for c in seeded]:
            raise ValueError('recorded seed plan differs from trusted recipe expansion')
        regenerated = expand_gate_seeded_cases(recipe, tuple_value, seed)
        # Timestamp records original generation; deterministic identity, axes,
        # recipe, tuple & expected case set remain independently verified.
        keys = ('id', 'kind', 'version', 'block', 'inputs', 'coverage', 'seed', 'tuple', 'recipe', 'expectedCaseSetHash')
        if len(seeded) != len(regenerated) or any(any(a[k] != b[k] for k in keys) for a, b in zip(seeded, regenerated)):
            raise ValueError('seed artifact differs from trusted recipe expansion')
        commands = next(p['commands'] for p in plan['seedPlan'] if p['block'] == recipe['block'])
        for cmd in commands:
            if file_hash(cmd['manifest']) != cmd['manifestHash']:
                raise ValueError('seed probe manifest changed since recorded plan')
    collected = collect(cases + seed_cases, roots, exclude_capture_dirs)
    out = fresh_output(output)
    reports = []
    for recipe in recipes:
        selected = [c for c in cases if c['block'] == recipe['block']]
        validate_batch(load_artifact(Path(manifests_dir) / (recipe['block'] + '.json')), selected)
        seeded = [c for c in seed_cases if c['block'] == recipe['block']]
        ids = {c['id'] for c in selected + seed_cases if c['block'] == recipe['block']}
        reports.append(evaluate_gate(recipe=recipe, cases=selected,
            captures=[c for c in collected['captures'] if c['case']['id'] in ids],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=config.get('normalizers', []),
            expected_cases=selected, seed=seed, random_case_factory=lambda _, frozen=seeded: frozen))
    value = {'status': 'blocked', 'seed': seed, 'seedOrigin': 'previously-recorded-runtime-plan',
             'plan': {'path': str(Path(plan_path).resolve()), 'hash': file_hash(plan_path)},
             'caseDenominator': len(cases), 'seedCaseDenominator': len(seed_cases),
             'nativeCaptureCount': len(collected['captures']), 'parityGranted': False,
             'gateResults': reports, 'collectionDiagnostics': collected['diagnostics']}
    value['supersededArchives'] = collected['supersededArchives']
    write_artifact(out / 'gate-results.json', value)
    write_artifact(out / 'captures.json', collected['captures'])
    write_artifact(out / 'collection.json', {k: v for k, v in collected.items() if k != 'captures'})
    return value


def font_addendum(output, roots, cases_dir, resource_path, private_collection_path, typecheck_path, binding_path):
    """Separate measured font candidate; never changes fixed81 denominator."""
    cases = [load_artifact(p) for p in sorted(Path(cases_dir).glob('*.json'))]
    collected = collect(cases, roots)
    # Native resource/control receipts retain raw measured JSON floats; refs
    # bind exact bytes rather than converting those upstream measurements.
    resource = load_raw_json(resource_path)
    resource_root = Path(resource_path).parent
    for part in ('font', 'license'):
        if file_hash(resource_root / resource[part]['path']) != resource[part]['sha256']:
            raise ValueError('font resource/license raw hash binding mismatch')
    private = load_raw_json(private_collection_path)
    if private.get('resourceHash') != resource['font']['sha256']:
        raise ValueError('private DirectWrite collection binds different font resource')
    observed = load_artifact(typecheck_path)
    typecheck_root = Path(typecheck_path).parent
    checks = []
    for row in observed['sources']:
        source_path = typecheck_root / row['source']
        stem = source_path.stem
        refs = {'source': source_path, 'stderr': typecheck_root / (stem + '.typecheck.stderr.txt'), 'stdout': typecheck_root / (stem + '.typecheck.stdout.txt')}
        for key, path in refs.items():
            if file_hash(path) != 'sha256:' + row[key + 'Hash'].removeprefix('sha256:'):
                raise ValueError('font Swift API typecheck raw source/diagnostic hash mismatch')
        checks.append({**row, 'archives': {k: {'path': str(p.resolve()), 'hash': file_hash(p)} for k, p in refs.items()}})
    out = fresh_output(output)
    refs = {name: {'path': str(Path(p).resolve()), 'hash': file_hash(p)} for name, p in
            [('resource', resource_path), ('privateDirectWriteControl', private_collection_path),
             ('swiftAPITypecheck', typecheck_path), ('pilotBinding', binding_path)]}
    value = {'kind': 'font-pilot-addendum', 'fixedCaseDenominatorUnchanged': 81, 'candidateOnly': True,
             'nativeMacCaptureCount': len(collected['captures']), 'nativeWindowsCaptureCount': 0,
             'resourceHash': resource['font']['sha256'], 'refs': refs, 'swiftAPITypechecks': checks,
             'selectedRoots': collected['selectedRoots'], 'collectionDiagnostics': collected['diagnostics'],
             'qualification': 'unqualified', 'parityGranted': False}
    write_artifact(out / 'font-addendum.json', value)
    write_artifact(out / 'collection.json', {k: v for k, v in collected.items() if k != 'captures'})
    write_artifact(out / 'captures.json', collected['captures'])
    (out / 'FONT.md').write_text('# Tinos candidate addendum\n\n'
        + f"{len(collected['captures'])} Mac candidate captures; fixed81case denominator unchanged. "
        + 'Process CoreText resource & private DirectWrite collection measured separately. '
        + 'Actual Windows Swift API typecheck rejects Font.custom & lineLimit.\n\n'
        + '[Bound resource/control/typecheck refs](font-addendum.json) · [Raw Mac archives](collection.json)\n')
    return value
