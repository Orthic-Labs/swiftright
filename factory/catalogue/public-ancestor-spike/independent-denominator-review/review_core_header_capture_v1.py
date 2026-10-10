#!/usr/bin/env python3
"""Read-only raw fact reconstruction; writes only this review directory."""
import collections
import hashlib
import importlib.util
import json
import re
import shlex
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CAPTURE = ROOT / 'factory/catalogue/public-ancestor-spike/core-header-index-v1'
LINK = ROOT / 'factory/catalogue/compiler-cursor-spike/link-evidence.json'
HELPER = ROOT / 'factory/catalogue/module-provenance-spike/exact_validator.py'
V12 = ROOT / 'factory/catalogue/evidence/interface-audit-v12-candidate.json'

def digest(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()

def descriptor(path, expected=None):
    path = Path(path)
    data = path.read_bytes()
    actual = digest(data)
    if expected is not None:
        assert actual == expected, (str(path), actual, expected)
    return {'path': str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path), 'sha256': actual, 'bytes': len(data)}

def write(name, value):
    (HERE / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def main():
    link_pin = descriptor(LINK, 'sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec')
    helper_pin = descriptor(HELPER, 'sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5')
    v12_pin = descriptor(V12, 'sha256:6f0384e8dfaa1bb21f96c3153cb02425912b6425cfdd534eb01a7f2ab71e1d13')
    link = json.loads(LINK.read_text())
    interface = next(i for i in link['interfaces'] if i['module'] == 'SwiftUICore')
    source_pin = descriptor(interface['path'], interface['sha256'])
    source = Path(interface['path']).read_text()
    old_index_pin = descriptor(ROOT / interface['indexOutput'], interface['indexOutputSha256'])
    old_request_pin = descriptor(ROOT / interface['indexRequest'], interface['indexRequestSha256'])
    receipt = json.loads((CAPTURE / 'run-receipt.json').read_text())
    actual_pins = []
    def walk(value):
        if isinstance(value, dict):
            if 'path' in value and 'sha256' in value:
                p = Path(value['path'])
                actual_pins.append(descriptor(p if p.is_absolute() else ROOT / p, value['sha256']))
            for item in value.values(): walk(item)
        elif isinstance(value, list):
            for item in value: walk(item)
    walk(receipt)
    assert receipt['sourcekit']['exit'] == 0
    assert receipt['sourcekit']['cwd'] == str(ROOT)
    assert receipt['sourcekit']['argv'] == ['xcrun', 'sourcekit-lsp', 'debug', 'run-sourcekitd-request', '--request-file', str(CAPTURE / 'request-index-core-header.yaml')]
    headers = [line for line in source.splitlines() if line.startswith('// swift-module-flags: ') or line.startswith('// swift-module-flags-ignorable: ')]
    assert len(headers) == 2
    flags = [token for line in headers for token in shlex.split(line.split(': ', 1)[1])]
    args = [interface['path']]
    removed = []
    i = 0
    while i < len(flags):
        token = flags[i]
        if token in {'-target', '-target-variant', '-target-arch-variant'}:
            removed.append(flags[i:i+2]); i += 2; continue
        args.extend(['-Xfrontend', token] if token in {'-enable-objc-interop', '-formal-cxx-interoperability-mode=off'} else [token])
        i += 1
    args += ['-sdk', link['toolchainEvidence']['sdk'], '-target', link['toolchainEvidence']['target']]
    request = (CAPTURE / 'request-index-core-header.yaml').read_text()
    request_args = json.loads('[' + re.search(r'key.compilerargs:\s*\[(.*?)\]', request, re.S)[1] + ']')
    assert request_args == args
    spec = importlib.util.spec_from_file_location('frozen_raw_helper', HELPER)
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    old = helper.entities((ROOT / interface['indexOutput']).read_text())
    raw = (CAPTURE / 'sourcekit-index-core-header.stdout').read_text()
    new = helper.entities(raw)
    key = lambda e: tuple(e.get(f) for f in ('line', 'column', 'kind', 'name'))
    old_keys = collections.Counter(map(key, old)); new_keys = collections.Counter(map(key, new))
    assert old_keys == new_keys and len(old) == len(new) == 8506 and all(n == 1 for n in new_keys.values())
    fresh = {key(e): e for e in new}
    usr_changes = sum(e['usr'] != fresh[key(e)]['usr'] for e in old)
    access_changes = collections.Counter((e.get('effective_access'), fresh[key(e)].get('effective_access')) for e in old if e.get('effective_access') != fresh[key(e)].get('effective_access'))
    assert usr_changes == 8395
    assert access_changes == {('source.decl.effective_access.fileprivate', 'source.decl.effective_access.package'): 302}
    public = [e for e in new if e.get('effective_access') == 'source.decl.effective_access.public']
    assert len(public) == 5198
    assert raw.count('key.effective_access: source.decl.effective_access.public') == 7515
    graph_pins = []; graph_ids = []
    for inp in link['rawGraphInputs']:
        graph_pins.append(descriptor(ROOT / inp['path'], inp['sha256']))
        graph_ids.extend(r['identifier']['precise'] for r in json.loads((ROOT / inp['path']).read_text())['symbols'])
    graph = set(graph_ids)
    assert len(graph_ids) == len(graph) == 108272
    closure = json.dumps(sorted(graph), separators=(',', ':')).encode()
    assert digest(closure) == link['rawGraphUsrClosure']['rawGraphUsrSetSha256']
    audit = json.loads(V12.read_text())
    rows = audit.get('declarations', audit.get('rows'))
    rows = [r for r in rows if r['module'] == 'SwiftUICore' and r.get('sourceKitEvidence', {}).get('linkEligibility') is True]
    old_join = collections.defaultdict(list)
    for entity in old: old_join[(entity['line'], entity['usr'])].append(entity)
    joined = []
    for row in rows:
        matches = old_join[(row['line'], row['symbol']['usr'])]
        assert len(matches) == 1
        entity = matches[0]; canonical = fresh[key(entity)]
        joined.append({'line': entity['line'], 'column': entity['column'], 'kind': entity['kind'], 'compilerName': entity['name'], 'oldUsr': entity['usr'], 'canonicalUsr': canonical['usr'], 'canonicalGraphPresent': canonical['usr'] in graph})
    assert len(joined) == 1378 and all(r['oldUsr'] != r['canonicalUsr'] for r in joined)
    assert sum(r['canonicalGraphPresent'] for r in joined) == 149
    write('core-header-v12-physical-joins-v1.json', joined)
    capture_files = [descriptor(p) for p in sorted(CAPTURE.rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc']
    dependencies = [link_pin, helper_pin, v12_pin, source_pin, old_index_pin, old_request_pin, *graph_pins, *actual_pins]
    dependencies = list({d['path']: d for d in dependencies}.values())
    write('core-header-capture-archive-v1.json', {'kind': 'explicit-raw-capture-archive-list', 'captureFiles': capture_files, 'requiredDependencies': dependencies, 'dependencyPolicy': 'Existing repository raw inputs retained through exact tracked pins; external SDK source & executable bytes identified by absolute paths & hashes. No derived count supplies authority.', 'excluded': ['__pycache__', '*.pyc']})
    write('core-header-capture-review-v1.json', {'kind': 'independent-core-header-raw-capture-review', 'version': 1, 'status': 'cleared-raw-facts-only', 'reviewerScript': descriptor(Path(__file__)), 'source': source_pin, 'sourceHeaderRows': headers, 'headerRowsSha256': digest(('\n'.join(headers)+'\n').encode()), 'headerTransformation': {'compilerArgs': args, 'removedTargetFlags': removed, 'frontendForwarding': ['-enable-objc-interop', '-formal-cxx-interoperability-mode=off'], 'requestMatchedExactly': True}, 'pins': dependencies, 'captureFiles': capture_files, 'findings': {'physicalDeclarationKeysOld': 8506, 'physicalDeclarationKeysNew': 8506, 'physicalKeysUnchanged': 8506, 'duplicatePhysicalKeys': 0, 'usrChanges': 8395, 'actualPublicDeclarationRecords': 5198, 'nestedPublicAccessFieldOccurrences': 7515, 'nestedPublicFieldOccurrencesAreNotDeclarationCount': True, 'fileprivateToPackageRecords': 302, 'rawGraphRows': 108272, 'rawGraphUniqueUsrs': 108272, 'canonicalPublicRawGraphPresent': sum(e['usr'] in graph for e in public), 'canonicalPublicRawGraphAbsent': sum(e['usr'] not in graph for e in public), 'v12ExactPhysicalJoins': 1378, 'v12CanonicalUsrChanges': 1378, 'v12CanonicalGraphPresent': 149, 'v12UnmatchedRows': 0}, 'joinPreimage': descriptor(HERE / 'core-header-v12-physical-joins-v1.json'), 'archiveList': descriptor(HERE / 'core-header-capture-archive-v1.json'), 'scope': 'Actual raw physical identity, exact source-header request, process receipt/tool bytes & immutable lineage reconciliation. Public ancestor eligibility, canonical tree proof & denominator completeness require separate frozen production review.'})
    print('Frozen independent raw facts: 8506 physical keys; 8395 changed USRs; 5198 public records; 302 package transitions; 1378 v12 joins; 149 graph present.')

if __name__ == '__main__': main()
