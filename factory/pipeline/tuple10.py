"""Additive tuple10 candidate profiles & explicit postclosure binding checks."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re

from factory.core.artifacts import artifact_ref, canonical_hash, file_hash, load_artifact, write_artifact
from factory.gate.core import baseline_case_refs
from factory.recipes.cases import expand_cases
from factory.recipes.recipes import load_recipes
from factory.pipeline.workflow import HERE, ROOT, fresh_output, synthetic, prepare

MEMBERS = ('Renderer DLL', 'FreshOnBridge.exe', 'WorkloadWin.exe', 'BridgeSmoke.exe',
           'BridgePixels.exe', 'TextGeom06.exe', 'Modal06.exe', 'ColdOpen06.exe')


def raw_ref(path):
    path = Path(path).resolve()
    return {'path': str(path), 'hash': file_hash(path)}


def staging_pins(path):
    text = Path(path).read_text()
    matches = re.findall(r'\| ([^|]+) \| `([^`]+)`(?:[^|]*)\| [^|]+ \| `([0-9A-Fa-f]{64})` \|', text)
    pins = {}
    for name, native_path, digest in matches:
        name = name.strip()
        if name in MEMBERS:
            if name in pins:
                raise ValueError('duplicate tuple10 staged pin')
            pins[name] = {'nativePath': native_path, 'hash': 'sha256:' + digest.lower()}
    if set(pins) != set(MEMBERS):
        raise ValueError('tuple10 staging lacks exact complete member pins')
    commits = re.findall(r'\b[0-9a-f]{40}\b', text)
    if not commits:
        raise ValueError('tuple10 staging lacks full source commit')
    return {'members': pins, 'stagedRuntimeCommit': commits[0]}


def utc(value):
    if not isinstance(value, str) or not value.endswith('Z'):
        raise ValueError('measurement timestamps must be explicit UTC')
    return datetime.fromisoformat(value[:-1] + '+00:00')


def validate_host_receipt(path, platform, runtime, closure, closure_receipt_hash, latest_at=None):
    """Fixed host receipt precedes tuple; per-case binary refs stay capture provenance."""
    path = Path(path).resolve()
    host = load_artifact(path)
    if (synthetic(host) or host.get('platform') != platform or host.get('tupleIndependent') is not True
            or host.get('runtimeCommit') != runtime):
        raise ValueError('host receipt must bind platform/own runtime & independent tuple identity')
    if utc(host.get('measuredAt')) <= utc(closure.get('closedAt')):
        raise ValueError('host measurement must occur after closure')
    if latest_at is not None and utc(host.get('measuredAt')) > utc(latest_at):
        raise ValueError('host measurement must precede final measurement binding')
    binding = host.get('closure', {})
    for key in ('tuple', 'decision', 'statusHash', 'closedAt'):
        if binding.get(key) != closure.get(key):
            raise ValueError('host receipt closure binding differs')
    if binding.get('receiptHash') != closure_receipt_hash:
        raise ValueError('host receipt closure archive differs')
    refs = {}
    for key in ('source', 'binary'):
        ref = host.get(key, {})
        source = Path(ref['path'])
        if not source.is_absolute():
            source = path.parent / source
        if file_hash(source) != ref.get('hash'):
            raise ValueError('host measured source/binary raw bytes differ')
        refs[key] = raw_ref(source)
    # Extra source receipts are checked when present; no tuple/case refs enter identity.
    for key in ('adapterSource', 'compiledAdapter', 'plan', 'compileObservation', 'runtimeSourceReceipt'):
        if key in host:
            ref = host[key]; source = Path(ref['path'])
            if not source.is_absolute(): source = path.parent/source
            if file_hash(source) != ref.get('hash'): raise ValueError('host adapter source bytes differ')
            refs[key] = raw_ref(source)
    if platform == 'windows':
        for key in ('plan', 'compileObservation', 'runtimeSourceReceipt'):
            if key not in refs: raise ValueError('Windows actual plan/compile/runtime source receipts required')
        plan = load_artifact(refs['plan']['path'])
        # Actual PowerShell observation may retain UTF-8 BOM; preserve raw hash above.
        from factory.pipeline.workflow import load_raw_json
        observation = load_raw_json(refs['compileObservation']['path'])
        runtime_receipt = load_artifact(refs['runtimeSourceReceipt']['path'])
        if any(synthetic(value) for value in (plan, observation, runtime_receipt)):
            raise ValueError('synthetic nested Windows host receipts rejected')
        if (plan.get('runtimeSourceCommit') != runtime or observation.get('runtimeSourceCommit') != runtime
                or runtime_receipt.get('sourceCommit') != runtime or observation.get('exitCode') != 0
                or 'sha256:' + observation.get('exeSha256', '') != refs['binary']['hash']
                or observation.get('planSha256') != refs['plan']['hash'].removeprefix('sha256:')
                or observation.get('sourceHash') != plan.get('sourceHash')
                or plan.get('runtimeSourceReceiptHash') != refs['runtimeSourceReceipt']['hash']
                or observation.get('runtimeSourceTreeHash') != runtime_receipt.get('sourceTreeHash')
                or plan.get('runtimeSourceTreeHash') != runtime_receipt.get('sourceTreeHash')
                or canonical_hash(runtime_receipt.get('sourceBindings')) != runtime_receipt.get('sourceTreeHash')
                or utc(observation.get('observedAt')) <= utc(closure.get('closedAt'))):
            raise ValueError('Windows compiled binary/source/runtime/postclosure bindings differ')
        package = Path(refs['plan']['path']).parent
        bindings = plan.get('sourceBindings')
        if not isinstance(bindings, list) or not bindings:
            raise ValueError('Windows qualification host compiled source bindings required')
        for binding in bindings:
            source = (package/binding['path']).resolve()
            if not source.is_relative_to(package) or file_hash(source) != binding['sha256']:
                raise ValueError('Windows qualification host compiled source drift')
    return refs


def closure_check(status_path=ROOT/'docs/sr0-status.md', staging_path=ROOT/'docs/sr0-tuple10-staging.md',
                  closure_receipt=None, measurements=None):
    """Never infer closure from stage passes, old tuples, or existence of binaries."""
    status = Path(status_path).read_text()
    pins = staging_pins(staging_path)
    result = {'kind': 'tuple10-closure-check', 'status': 'blocked', 'bound': False,
              'refs': {'status': raw_ref(status_path), 'staging': raw_ref(staging_path)},
              'stagedPins': pins, 'issues': []}
    overall = re.findall(r'^\*\*Overall:\s*(.+?)\*\*', status, re.M)
    if len(overall) != 1 or not re.match(r'SR0 is CLOSED\b', overall[0]) or not re.search(r'tuple\s*0?10\b', overall[0], re.I):
        result['issues'].append('docs/sr0-status.md must explicitly declare Overall SR0 CLOSED on tuple10')
    if closure_receipt is None or measurements is None:
        result['issues'].append('postclosure closure receipt & measured frozen contract/ABI/runtime binding required')
        return result
    closure, measured = load_artifact(closure_receipt), load_artifact(measurements)
    result['refs'].update({'closureReceipt': raw_ref(closure_receipt), 'measurements': raw_ref(measurements)})
    if synthetic(closure) or synthetic(measured):
        result['issues'].append('synthetic closure/binding evidence rejected')
    if closure.get('tuple') != '10' or closure.get('statusHash') != result['refs']['status']['hash'] or closure.get('decision') != 'CLOSED':
        result['issues'].append('closure receipt must bind exact CLOSED tuple10 status bytes')
    try:
        closed_at, measured_at = utc(closure.get('closedAt')), utc(measured.get('measuredAt'))
        if measured_at <= closed_at:
            result['issues'].append('contract/ABI measurements must occur after closure')
    except (ValueError, TypeError):
        result['issues'].append('valid postclosure measurement timestamps required')
    if measured.get('closureStatusHash') != result['refs']['status']['hash'] or measured.get('stagingHash') != result['refs']['staging']['hash']:
        result['issues'].append('measurements must bind current closure & exact staging bytes')
    if measured.get('stagedPins') != pins:
        result['issues'].append('measured staged pins differ from exact tuple10 staging record')
    runtime = measured.get('runtimeCommit')
    if not isinstance(runtime, str) or not re.fullmatch('[0-9a-f]{40}', runtime) or runtime == pins['stagedRuntimeCommit']:
        result['issues'].append('changed factory runtime needs own full commit separate from staged runtime')
    for key in ('contract', 'abi'):
        evidence = measured.get(key, {})
        try:
            if evidence.get('hash') != file_hash(evidence['path']):
                raise ValueError('raw hash mismatch')
            result['refs'][key] = raw_ref(evidence['path'])
        except (KeyError, OSError, ValueError):
            result['issues'].append(f'{key} actual archive hash binding required')
    if measured.get('contract', {}).get('state') != 'frozen':
        result['issues'].append('frozen contract measurement required')
    elif 'contract' in result['refs']:
        contract_text = Path(measured['contract']['path']).read_text()
        if not re.search(r'^\s*(?:\*\*)?Status:\s*FROZEN\b', contract_text, re.M | re.I):
            result['issues'].append('contract archive must explicitly declare Status FROZEN')
    if not measured.get('abi', {}).get('version'):
        result['issues'].append('measured ABI version required')
    elif 'abi' in result['refs']:
        abi = load_artifact(measured['abi']['path'])
        if (synthetic(abi) or abi.get('tuple') != '10' or abi.get('runtimeCommit') != runtime
                or abi.get('rendererHash') != pins['members']['Renderer DLL']['hash']
                or abi.get('version') != measured['abi']['version']):
            result['issues'].append('ABI observation must bind measured time/tuple/renderer/own runtime/version')
        try:
            if not utc(closure.get('closedAt')) < utc(abi.get('measuredAt')) <= utc(measured.get('measuredAt')):
                raise ValueError('ABI time outside postclosure measurement interval')
        except (ValueError, TypeError):
            result['issues'].append('ABI observation timestamp must follow closure & precede final measurement')
    # Both platform host measurements bind newly built factory hosts, never old r09 archives.
    for platform in ('macos', 'windows'):
        host = measured.get('hosts', {}).get(platform, {})
        try:
            if host.get('runtimeCommit') != runtime or file_hash(host['path']) != host.get('hash'):
                raise ValueError('host/runtime mismatch')
            result['refs'][platform + 'Host'] = raw_ref(host['path'])
            result.setdefault('hostMeasurements', {})[platform] = validate_host_receipt(
                host['path'], platform, runtime, closure, file_hash(closure_receipt), measured.get('measuredAt'))
        except (KeyError, OSError, ValueError):
            result['issues'].append(f'new {platform} factory host bytes & own runtime commit required')
    if not result['issues']:
        result.update(status='candidate-binding-ready', bound=True, runtimeCommit=runtime,
                      hostHashes={p: measured['hosts'][p]['hash'] for p in ('macos', 'windows')},
                      rendererHash=pins['members']['Renderer DLL']['hash'])
    return result


def prepare_candidate(output, status_path=ROOT/'docs/sr0-status.md', staging_path=ROOT/'docs/sr0-tuple10-staging.md',
                      closure_receipt=None, measurements=None):
    """Build reviewed-profile-ready config without accepting review or qualification."""
    check = closure_check(status_path, staging_path, closure_receipt, measurements)
    original = load_artifact(HERE/'inputs/cases.json')
    old_tuple = load_artifact(HERE/'inputs/observed-tuple.json')
    config = load_artifact(HERE/'inputs/acceptance-candidate.json')
    profile, counts = [], {}
    for recipe in load_recipes():
        expanded = expand_cases(recipe, old_tuple, seed=0)['cases']
        old_cases = [c for c in original if c['block'] == recipe['block']]
        if baseline_case_refs(expanded) != baseline_case_refs(old_cases):
            raise ValueError('seed0 no longer reproduces fixed81 recipe population')
        profile.append({'recipe': artifact_ref(recipe), 'seed': 0, 'cases': baseline_case_refs(expanded)})
        counts[recipe['block']] = len(expanded)
    if sum(counts.values()) != 81:
        raise ValueError('fixed81 recipe population changed')
    config.update(baseline={'version': '1', 'recipes': profile}, review='pending-maintainer-review', mode='observational')
    out = fresh_output(output)
    write_artifact(out/'acceptance-candidate.json', config)
    write_artifact(out/'closure-check.json', check)
    template = {'kind': 'tuple10-measurement-template', 'tuple': '10', 'bound': False,
                'closureStatusHash': None, 'stagingHash': check['refs']['staging']['hash'],
                'stagedPins': check['stagedPins'], 'runtimeCommit': None, 'measuredAt': None,
                'contract': {'path': None, 'hash': None, 'state': None},
                'abi': {'path': None, 'hash': None, 'version': None},
                'hosts': {p: {'path': None, 'hash': None, 'runtimeCommit': None} for p in ('macos', 'windows')}}
    write_artifact(out/'measurement-template.json', template)
    if check['bound']:
        # New tuple has independently measured hosts/runtime; captures must be newly acquired.
        measured = load_artifact(measurements)
        required = ('macosBuild', 'sdk', 'toolchains', 'factoryVersion')
        if any(not measured.get(k) for k in required):
            raise ValueError('measured platform/toolchain/factory identity required')
        tuple_value = {k: measured[k] for k in required}
        tuple_value.update(id='sr1-tuple10-own-runtime-candidate', acceptanceConfigHash=canonical_hash(config),
                           runtimeCommit=check['runtimeCommit'], rendererHash=check['rendererHash'], hostHashes=check['hostHashes'])
        write_artifact(out/'observed-tuple-candidate.json', tuple_value)
    else:
        write_artifact(out/'tuple-template.json', {'bound': False, 'tuple': '10', 'runtimeCommit': None,
            'hostHashes': {'macos': None, 'windows': None}, 'acceptanceConfigHash': canonical_hash(config),
            'stagedPins': check['stagedPins'], 'required': ['explicit CLOSED tuple10 status', 'postclosure frozen contract & ABI', 'own changed-runtime commit', 'new platform hosts & captures']})
    summary = {'kind': 'tuple10-candidate-summary', 'mode': 'candidate-preparation', 'bound': check['bound'],
               'acceptedDenominator': False, 'review': config['review'], 'baselineSeed': 0, 'caseDenominator': 81,
               'profileCounts': counts, 'closureIssues': check['issues'], 'parityGranted': False,
               'originalCases': raw_ref(HERE/'inputs/cases.json'), 'configHash': canonical_hash(config),
               'nativeCaptureRequirement': 'new Mac & Windows captures on exact new tuple; historical archives remain preserved'}
    write_artifact(out/'prepare-summary.json', summary)
    return summary


def finalize_bundle(output, status_path, staging_path, closure_receipt, measurements):
    """Materialize F4 bundle only after closure & independent host measurement validation."""
    check = closure_check(status_path, staging_path, closure_receipt, measurements)
    if not check['bound']:
        raise ValueError('final bundle requires explicit CLOSEDtuple10 & measured independent hosts: ' + '; '.join(check['issues']))
    summary = prepare_candidate(output, status_path, staging_path, closure_receipt, measurements)
    out = Path(output).resolve()
    prepare(out/'expanded', out/'observed-tuple-candidate.json', out/'acceptance-candidate.json', seed=0)
    cases = load_artifact(out/'expanded/cases.json')
    probes = load_artifact(out/'expanded/probe-manifests.json')
    old_primaries = load_artifact(HERE/'inputs/primary-cases.json')
    order = ('swiftui.shapes.fill-stroke', 'swiftui.image', 'swiftui.stack-overlay', 'swiftui.text.bundled-font',
             'swiftui.custom-layout', 'swiftui.disabled', 'swiftui.padding-frame', 'swiftui.preference-key', 'swiftui.scroll-view', 'swiftui.toggle')
    primaries = []
    for block in order:
        old = next(p for p in old_primaries if p['block'] == block)
        case = next(c for c in cases if c['id'] == old['case'])
        probe = next(p for p in probes if p['case'] == artifact_ref(case))
        path = out/'expanded/probes'/Path(probe['sourceFile']).with_suffix('.manifest.json')
        primaries.append({'block': block, 'case': case['id'], 'caseRef': artifact_ref(case),
                          'recipe': probe['recipe'], 'sourceHash': probe['sourceHash'], 'manifestPath': str(path), 'manifestHash': file_hash(path)})
    write_artifact(out/'primary-cases.json', primaries)
    write_artifact(out/'bundle.json', {'kind': 'tuple10-f4-candidate-bundle', 'caseDenominator': len(cases),
        'primaries': primaries, 'caseRoot': str(out/'expanded/cases'), 'cases': raw_ref(out/'expanded/cases.json'),
        'tuple': raw_ref(out/'observed-tuple-candidate.json'), 'config': raw_ref(out/'acceptance-candidate.json'),
        'runtimeCommit': check['runtimeCommit'], 'parityGranted': False,
        'seedPlan': 'generate fresh recorded own-seed plan against exact new tuple; no old seeded refs eligible'})
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'closure-check', 'finalize'))
    parser.add_argument('--output', required=True)
    parser.add_argument('--status', default=str(ROOT/'docs/sr0-status.md'))
    parser.add_argument('--staging', default=str(ROOT/'docs/sr0-tuple10-staging.md'))
    parser.add_argument('--closure-receipt')
    parser.add_argument('--measurements')
    args = parser.parse_args()
    if args.command == 'finalize':
        result = finalize_bundle(args.output, args.status, args.staging, args.closure_receipt, args.measurements)
    elif args.command == 'prepare':
        result = prepare_candidate(args.output, args.status, args.staging, args.closure_receipt, args.measurements)
    else:
        result = closure_check(args.status, args.staging, args.closure_receipt, args.measurements)
        write_artifact(fresh_output(args.output)/'closure-check.json', result)
    print(json.dumps({k: result[k] for k in ('status', 'bound', 'caseDenominator', 'baselineSeed') if k in result}))
    return 0 if result['bound'] else 3


if __name__ == '__main__':
    raise SystemExit(main())
