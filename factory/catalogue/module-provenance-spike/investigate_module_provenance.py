#!/usr/bin/env python3
"""Production reconstruction & byte-distinct raw fault replay for immutable836."""
from __future__ import annotations
import json
import re
from pathlib import Path
from exact_validator import Validator, HERE, ROOT, LINK, EXPECTED_LINK, DEMANGLE, digest, require


def replace_record(raw, usr, field, old, new, duplicate=False, implicit_duplicate=False):
    """Edit exactly one raw SourceKit record, never derived receipts."""
    token_usr = 'key.usr: ' + json.dumps(usr) + ','
    pattern_record = re.compile(r'(?m)^( +)key\.kind: source\.lang\.swift\.decl\.[^\n]+\n\1key\.name: [^\n]+\n\1' + re.escape(token_usr))
    candidates = list(pattern_record.finditer(raw))
    require(len(candidates) == 1, 'ambiguous raw declaration mutation USR')
    match = candidates[0]; indent = match[1][:-2]
    begin = raw.rfind(indent + '{\n', 0, match.start())
    require(begin >= 0, 'missing raw declaration open')
    closed = re.search(r'(?m)^' + re.escape(indent) + r'\},?', raw[match.end():])
    require(closed is not None, 'missing raw record close')
    end = match.end() + closed.end(); block = raw[begin:end]
    if duplicate:
        duplicate_block = block
        if implicit_duplicate:
            duplicate_block = block.replace(indent + '{\n', indent + '{\n' + indent + '  key.is_implicit: 1,\n', 1)
        modified = block + '\n' + duplicate_block
    else:
        pattern = re.compile(r'(?m)^' + re.escape(indent + '  ') + r'key\.' + re.escape(field) + r': ([^\n]+)$')
        fields = list(pattern.finditer(block)); require(len(fields) == 1, 'ambiguous raw field mutation')
        found = fields[0]; previous = found[1].removesuffix(',')
        decoded = json.loads(previous) if previous.startswith('"') else int(previous) if previous.isdigit() else previous
        require(decoded == old, 'raw field old identity mismatch')
        value = json.dumps(new) if previous.startswith('"') else str(new)
        replacement = value + (',' if found[1].endswith(',') else '')
        modified = block[:found.start(1)] + replacement + block[found.end(1):]
    return raw[:begin] + modified + raw[end:]


def run(output=HERE / 'module-provenance-evidence.json'):
    validator = Validator()
    baseline = validator.validate()
    controls = []

    def fault(label, key, altered):
        # Accepted full33 baseline immediately precedes every raw fault.
        require(len(validator.validate()) == 33, 'control positive baseline failed')
        original = validator.inputs[key]
        require(altered != original and digest(altered) != digest(original), 'unchanged fault bytes')
        candidate = dict(validator.inputs); candidate[key] = altered
        try:
            validator.validate(candidate)
        except ValueError as error:
            controls.append({'fault': label, 'rawInput': key, 'baselineAcceptedRows': 33, 'beforeSha256': digest(original), 'afterSha256': digest(altered), 'bytesDiffer': True, 'rejected': True, 'rejection': str(error)})
        else:
            raise ValueError('production accepted raw fault: ' + label)

    for row in baseline:
        member = row['member']; usr = member['usr']; label = ':'.join(map(str, row['key']))
        for field, changed in [('line', member['line'] + 1), ('name', '__WrongMember()'), ('usr', usr.replace('7SwiftUI', '11SwiftUICore', 1)), ('kind', 'source.lang.swift.decl.struct'), ('effective_access', 'source.decl.effective_access.private')]:
            fault(label + ':member-' + field, 'SwiftUI:index', replace_record(validator.inputs['SwiftUI:index'], usr, field, member[field], changed))
        fault(label + ':member-duplicate', 'SwiftUI:index', replace_record(validator.inputs['SwiftUI:index'], usr, '', '', '', duplicate=True))
        fault(label + ':member-implicit-duplicate', 'SwiftUI:index', replace_record(validator.inputs['SwiftUI:index'], usr, '', '', '', duplicate=True, implicit_duplicate=True))
        source = validator.inputs['SwiftUI:source'].splitlines(keepends=True); source[row['line'] - 1] = source[row['line'] - 1].replace(row['name'], '__WrongMember', 1)
        fault(label + ':member-source-name', 'SwiftUI:source', ''.join(source))
    origins = {row['origin']['usr']: row for row in baseline}
    for usr, row in origins.items():
        origin = row['origin']; label = 'origin:' + origin['name']
        for field, changed in [('line', origin['line'] + 1), ('name', '__WrongOrigin'), ('usr', usr.replace('11SwiftUICore', '7SwiftUI', 1)), ('kind', 'source.lang.swift.decl.enum'), ('effective_access', 'source.decl.effective_access.private')]:
            fault(label + ':' + field, 'SwiftUICore:index', replace_record(validator.inputs['SwiftUICore:index'], usr, field, origin[field], changed))
        fault(label + ':duplicate', 'SwiftUICore:index', replace_record(validator.inputs['SwiftUICore:index'], usr, '', '', '', duplicate=True))
        fault(label + ':implicit-duplicate', 'SwiftUICore:index', replace_record(validator.inputs['SwiftUICore:index'], usr, '', '', '', duplicate=True, implicit_duplicate=True))
        for change, transform in [('own-annotation', lambda s:s.replace('module: "SwiftUI"', 'module: "SwiftUICore"', 1)), ('platform-annotation', lambda s:s.replace('18.0', '19.0', 1))]:
            source = validator.inputs['SwiftUICore:source'].splitlines(keepends=True); line = row['originallyDefinedIn'][0]['line']; source[line-1] = transform(source[line-1]); fault(label + ':' + change, 'SwiftUICore:source', ''.join(source))
        source = validator.inputs['SwiftUICore:source'].splitlines(keepends=True); source[origin['line']-1] = source[origin['line']-1].replace(origin['name'], '__WrongNominal', 1); fault(label + ':source-name', 'SwiftUICore:source', ''.join(source))
        condition_line = row['originSource']['conditions'][-1]['line']; source = validator.inputs['SwiftUICore:source'].splitlines(keepends=True); source[condition_line-1] = source[condition_line-1].replace('$TildeSendable', '$WrongCondition', 1); fault(label + ':conditional', 'SwiftUICore:source', ''.join(source))
    first = baseline[0]
    source = validator.inputs['SwiftUI:source'].splitlines(keepends=True); index = first['extension']['line'] - 1; source[index] = source[index].replace('SwiftUICore.', 'SwiftUI.', 1); fault('extension-wrong-module', 'SwiftUI:source', ''.join(source))
    source = validator.inputs['SwiftUI:source'].splitlines(keepends=True); source[index] = source[index].replace('SwiftUICore.', 'SwiftUICore.__WrongOuter.', 1); fault('extension-wrong-full-owner', 'SwiftUI:source', ''.join(source))
    fault('reexport-wrong-module', 'SwiftUI:source', validator.inputs['SwiftUI:source'].replace('@_exported import SwiftUICore', '@_exported import SwiftUI', 1))
    for label, old, new in [('origin-expanded-kind', 'kind=Structure\n', 'kind=Enum\n'), ('extension-module', 'kind=Module, text="SwiftUI"', 'kind=Module, text="SwiftUICore"'), ('full-owner', 'kind=Identifier, text="_TestApp"', 'kind=Identifier, text="__WrongOwner"'), ('declaration-kind', 'kind=Function\n', 'kind=Variable\n'), ('direct-name', 'kind=Identifier, text="run"', 'kind=Identifier, text="__WrongMember"'), ('malformed-tree', 'kind=Global\n', 'kind=Global, unsupported=1\n')]:
        fault('demangle:' + label, 'trees', validator.inputs['trees'].replace(old, new, 1))
    section = re.search(r'Demangling for \$s.*?(?=Demangling for \$s|\Z)', validator.inputs['trees'], re.S)[0]
    fault('demangle:duplicate', 'trees', validator.inputs['trees'] + section)
    for module in ('SwiftUI', 'SwiftUICore'):
        for label, old, new in [('module', '"-module-name", "' + module + '"', '"-module-name", "WrongModule"'), ('target', 'arm64-apple-macosx27.0', 'x86_64-apple-macosx27.0'), ('source', 'key.sourcefile: "', 'key.sourcefile: "/wrong/')]:
            fault('request:' + module + ':' + label, module + ':request', validator.inputs[module + ':request'].replace(old, new, 1))
    tree_path = HERE / 'swift-demangle-module-expand-v2.txt'; tree_path.write_text(validator.inputs['trees'])
    provenance = {key: {'path': str(path), 'sha256': digest(path.read_bytes())} for key, path in validator.paths.items()}
    provenance['trees'] = {'path': str(tree_path), 'sha256': digest(tree_path.read_bytes()), 'command': validator.command, 'tool': {'path': str(DEMANGLE), 'sha256': validator.demangle_hash}}
    for key, filename in [('validator', 'exact_validator.py'), ('investigator', 'investigate_module_provenance.py'), ('test', 'test_module_provenance.py')]:
        path = HERE / filename; provenance[key] = {'path': str(path), 'sha256': digest(path.read_bytes())}
    provenance['immutable836'] = {'path': str(LINK), 'sha256': EXPECTED_LINK}
    for key, filename in [('bridgeLineage', 'factory/catalogue/residual-investigation/context-bridge-evidence.json'), ('v9Lineage', 'factory/catalogue/evidence/interface-audit-v9-candidate.json')]:
        path = ROOT / filename; provenance[key] = {'path': str(path), 'sha256': digest(path.read_bytes()), 'role': 'lineage-only; no identity authority'}
    provenance['toolchain'] = validator.link['toolchainEvidence']
    payload = {'kind': 'f1-module-provenance-investigation', 'version': 2, 'status': 'review-only-qualified-module-resolution', 'method': 'independent immutable836 signatures, raw single member/origin identities, full source scopes & branches, own contiguous annotations, freshly executed strict demangle trees & exact request/tool/source byte pins', 'resolution': {'rows': len(baseline), 'exactCrossModuleExtensionProof': len(baseline), 'exactOriginallyDefinedInAliasProof': len(baseline), 'strictBridgePromotion': 0, 'decision': 'retain holds; reconstructed per-nominal origin evidence requires policy review'}, 'inputs': provenance, 'controls': controls, 'rows': baseline}
    output.write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')) + '\n')
    return payload


if __name__ == '__main__':
    result = run(); print(json.dumps({'resolution': result['resolution'], 'rawFaultsRejected': len(result['controls'])}, sort_keys=True))
