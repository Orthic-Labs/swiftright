#!/usr/bin/env python3
"""Bounded compiler-branch reconstruction from immutable836 & actual raw bytes."""
from __future__ import annotations
import copy
from functools import lru_cache
from types import MappingProxyType
import importlib.util
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
HELPER = ROOT / 'factory/catalogue/module-provenance-spike/exact_validator.py'
HELPER_HASH = 'sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5'
import hashlib

def digest(raw):
    return 'sha256:' + hashlib.sha256(raw if isinstance(raw, bytes) else raw.encode()).hexdigest()

def require(ok, reason):
    if not ok:
        raise ValueError(reason)

require(digest(HELPER.read_bytes()) == HELPER_HASH, 'frozen parser helper changed')
spec = importlib.util.spec_from_file_location('inactive_frozen_module_parser', HELPER)
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
LINK = helper.LINK
EXPECTED_LINK = helper.EXPECTED_LINK
NAME = 'buildLimitedAvailability'
INACTIVE = 28491
ACTIVE = 28484
CONDITION = 'compiler(>=5.3) && $InlineAlways'
DEMANGLE_HASH = 'sha256:ae7da66c8a56fb3b90817c10eb816c82e25bf7a26ae0158effbda223f7f0fefe'
OWNER = ['WidgetBundleBuilder']
GRAPH_USRS = {'s:7SwiftUI19WidgetBundleBuilderV24buildLimitedAvailabilityyAA0C0_AA01_ghC6MarkerpxAaERzlFZ', 's:7SwiftUI19WidgetBundleBuilderV24buildLimitedAvailabilityyAA0C0_AA01_ghC6MarkerpxAA07ControlC0RzlFZ'}
SCRATCH = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/inactive-branch-v2')


def conditional_model(source):
    """Parse complete nested SDK conditional frames & exact per-line branches."""
    stack, frames, by_line = [], {}, {}
    for number, original in enumerate(source.splitlines(), 1):
        text = original.strip()
        if text.startswith('#if '):
            frame = {'ifLine': number, 'condition': text[4:], 'parentIfLines': [f['ifLine'] for f in stack], 'branches': [{'kind': 'if', 'line': number, 'expression': text[4:]}], 'endifLine': None}
            frames[number] = frame; stack.append(frame)
        elif text.startswith('#elseif ') or text == '#else':
            require(bool(stack), 'orphan conditional branch')
            frame = stack[-1]
            require(frame['branches'][-1]['kind'] != 'else', 'duplicate/late else branch')
            frame['branches'].append({'kind': 'elseif' if text.startswith('#elseif ') else 'else', 'line': number, 'expression': text[8:] if text.startswith('#elseif ') else None})
        elif text == '#endif':
            require(bool(stack), 'orphan endif')
            stack.pop()['endifLine'] = number
        by_line[number] = [{'ifLine': f['ifLine'], 'branchLine': f['branches'][-1]['line'], 'kind': f['branches'][-1]['kind'], 'condition': f['condition']} for f in stack]
    require(not stack, 'unterminated conditional')
    return frames, by_line


def request_identity(raw, operation, interface, sdk, target, offset=None):
    require(re.findall(r'key.request:\s*(\S+?)(?:,|\s)', raw) == ['source.request.' + operation], 'request operation mismatch')
    files = re.findall(r'key.sourcefile:\s*("[^"]+")', raw)
    require(files == [json.dumps(interface)], 'request source identity mismatch')
    args = re.findall(r'key.compilerargs:\s*\[([^\]]+)\]', raw)
    require(len(args) == 1, 'request argument cardinality mismatch')
    require(re.findall(r'"([^"]+)"', args[0]) == [interface, '-sdk', sdk, '-target', target, '-module-name', 'SwiftUI'], 'compiler request identity mismatch')
    if offset is not None:
        require(re.findall(r'key.offset:\s*(\d+)', raw) == [str(offset)], 'cursor offset mismatch')
        require(re.findall(r'key.name:\s*("[^"]+")', raw) == [json.dumps(interface)], 'cursor file name mismatch')


def function_owner(tree):
    roots = tree['children']
    require(len(roots) == 1 and roots[0]['kind'] == 'Static', 'missing exact static tree wrapper')
    nodes = roots[0]['children']
    require(len(nodes) == 1 and nodes[0]['kind'] == 'Function', 'wrong direct function tree kind')
    declaration = nodes[0]
    identifiers = [n for n in declaration['children'] if n['kind'] == 'Identifier']
    require(len(identifiers) == 1 and identifiers[0]['text'] == NAME, 'wrong direct function tree name')
    owners = [n for n in declaration['children'] if n['kind'] in helper.NOMINAL or n['kind'] == 'Extension']
    require(len(owners) == 1, 'ambiguous direct function owner')
    owner = owners[0]
    if owner['kind'] == 'Extension':
        modules = [n for n in owner['children'] if n['kind'] == 'Module']
        nominals = [n for n in owner['children'] if n['kind'] in helper.NOMINAL]
        require(len(modules) == len(nominals) == 1 and modules[0]['text'] == 'SwiftUI', 'wrong tree extension module')
        owner = nominals[0]
    module, path = helper.nominal_identity(owner)
    require(module == 'SwiftUI' and path == OWNER, 'wrong exact tree owner path/module')
    return {'module': module, 'path': path, 'static': True, 'kind': 'func', 'name': NAME}


def capture(argv, cwd):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, check=False)
    return {'argv': argv, 'cwd': str(cwd), 'exitCode': result.returncode, 'stdout': result.stdout.decode(), 'stderr': result.stderr.decode()}


class Validator:
    def __init__(self):
        require(digest(LINK.read_bytes()) == EXPECTED_LINK, 'immutable836 changed')
        self.link = json.loads(LINK.read_text())
        rows = [r for r in self.link['rows'] if (r['module'], r['interface'], r['line'], r['name']) == ('SwiftUI', 'arm64e-apple-macos.swiftinterface', INACTIVE, NAME)]
        require(len(rows) == 1, 'exact namespace allowlist mismatch'); self.row = rows[0]
        self.interface = next(i for i in self.link['interfaces'] if i['module'] == 'SwiftUI')
        self.sdk = self.link['toolchainEvidence']['sdk']; self.target = self.link['toolchainEvidence']['target']
        self.swiftc = Path(self.link['toolchainEvidence']['compiler']['driverPath'])
        self.inputs, self.paths, self.pins = {}, {}, {}
        def pinned(key, path, expected):
            path = Path(path); path = path if path.is_absolute() else ROOT / path
            raw = path.read_bytes(); require(digest(raw) == expected, 'immutable raw pin mismatch: ' + key)
            self.inputs[key] = raw.decode(); self.paths[key] = str(path); self.pins[key] = expected
        for key, path_key, hash_key in [('source', 'path', 'sha256'), ('index', 'indexOutput', 'indexOutputSha256'), ('indexRequest', 'indexRequest', 'indexRequestSha256')]:
            pinned(key, self.interface[path_key], self.interface[hash_key])
        cursor = self.link['controls']['conditionalBranchControls']['inactiveWidgetBundleOverload']['cursorInfo']
        for key, path_key, hash_key in [('cursorRequest', 'request', 'requestSha256'), ('cursorResponse', 'response', 'responseSha256')]:
            pinned(key, cursor[path_key], cursor[hash_key])
        graph = next(g for g in self.link['rawGraphInputs'] if g['path'] == 'factory/out/catalogue/raw/swiftui/SwiftUI.symbols.json')
        pinned('graph', graph['path'], graph['sha256'])
        for name in ('compiler', 'sourcekitd', 'sourcekitLsp'):
            record = self.link['toolchainEvidence'][name]; path = Path(record.get('executablePath', record.get('path')))
            raw = path.read_bytes(); require(digest(raw) == record['sha256'], 'tool executable pin mismatch: ' + name)
            self.paths['tool:' + name] = str(path); self.pins['tool:' + name] = record['sha256']
            self.inputs['tool:' + name] = raw
        require(self.swiftc.resolve() == Path(self.paths['tool:compiler']).resolve(), 'driver/frontend identity mismatch')
        self.anchor_entities = helper.entities(self.inputs['index'])
        self.anchor_graph = self.graph_candidates(self.inputs['graph'])
        self.anchor_models = helper.source_model(self.inputs['source'])
        require(self.row['sourceHash'] == self.pins['source'], 'row/source identity mismatch')
        # Fresh compiler invocation uses internal Mac scratch for all fresh binaries.
        SCRATCH.mkdir(parents=True, exist_ok=True)
        require(str(SCRATCH.resolve()).startswith('/Users/adrdsouza/Library/Caches/'), 'non-internal scratch rejected')
        self.probe_source = '#if ' + CONDITION + '\nprint("selected=InlineAlways")\n#else\nprint("selected=else")\n#endif\n'
        probe = SCRATCH / 'branch-probe.swift'; binary = SCRATCH / 'branch-probe'
        probe.write_text(self.probe_source)
        self.compile_argv = [str(self.swiftc), '-sdk', self.sdk, '-target', self.target, '-module-name', 'SwiftUI', '-module-cache-path', str(SCRATCH / 'module-cache'), str(probe), '-o', str(binary)]
        compiled = capture(self.compile_argv, SCRATCH)
        executed = capture([str(binary)], SCRATCH) if compiled['exitCode'] == 0 else {'argv': [str(binary)], 'cwd': str(SCRATCH), 'exitCode': None, 'stdout': '', 'stderr': 'not executed: compilation failed'}
        version = capture([str(self.swiftc), '-target', self.target, '--version'], SCRATCH)
        self.inputs['probeSource'] = probe.read_text()
        self.inputs['processResults'] = json.dumps({'compile': compiled, 'run': executed, 'version': version}, sort_keys=True, separators=(',', ':')) + '\n'
        self.process_anchor = self.inputs['processResults']
        usrs = sorted({e['usr'] for e in self.anchor_entities if (e['line'] == ACTIVE and e['name'] == NAME + '(_:)') or (e['line'] == 28369 and e['name'] == OWNER[0] and e['kind'] == 'source.lang.swift.decl.struct')} | GRAPH_USRS)
        require(digest(helper.DEMANGLE.read_bytes()) == DEMANGLE_HASH, 'frozen demangler tool pin mismatch')
        completed = subprocess.run([str(helper.DEMANGLE), '--expand', *['$s' + u[2:] for u in usrs]], capture_output=True, check=True, text=True)
        require(not completed.stderr, 'demangle stderr')
        self.inputs['trees'] = completed.stdout
        self.tree_usrs = usrs
        self.demangle_command = [str(helper.DEMANGLE), '--expand', *['$s' + u[2:] for u in usrs]]
        self.pins['demangler'] = DEMANGLE_HASH
        self.inputs['tool:demangler'] = helper.DEMANGLE.read_bytes()
        self.paths['tool:demangler'] = str(helper.DEMANGLE)
        self.pins['tool:demangler'] = DEMANGLE_HASH
        self.inputs = MappingProxyType(self.inputs)

    @staticmethod
    @lru_cache(maxsize=2)
    def _graph_candidate_json(raw):
        graph = json.loads(raw); require(graph['module']['name'] == 'SwiftUI', 'graph source module mismatch')
        candidates = [s for s in graph['symbols'] if s.get('pathComponents') == OWNER + [NAME + '(_:)']]
        require(len(candidates) == 2, 'ambiguous graph candidate cardinality mismatch')
        require({s['identifier']['precise'] for s in candidates} == GRAPH_USRS, 'exact graph USR set mismatch')
        for symbol in candidates:
            require(symbol['kind']['identifier'] == 'swift.type.method' and symbol['accessLevel'] == 'public', 'graph kind/access mismatch')
            require(symbol['names']['title'] == NAME + '(_:)', 'graph member name mismatch')
            require(symbol['swiftExtension']['extendedModule'] == 'SwiftUI', 'graph owner module mismatch')
            parameters = symbol['functionSignature']['parameters']
            require(len(parameters) == 1 and parameters[0]['name'] == 'widget', 'graph parameter cardinality/name mismatch')
            parameter = ''.join(f['spelling'] for f in parameters[0]['declarationFragments'])
            expected = 'widget: some ControlWidget' if 'ControlC0' in symbol['identifier']['precise'] else 'widget: some Widget'
            require(parameter == expected, 'exact ambiguous graph parameter signature mismatch')
            returns = ''.join(f['spelling'] for f in symbol['functionSignature']['returns'])
            require(returns == 'any Widget & _LimitedAvailabilityWidgetMarker', 'exact ambiguous graph return signature mismatch')
        return json.dumps(sorted(candidates, key=lambda s: s['identifier']['precise']), sort_keys=True, separators=(',', ':'))

    @staticmethod
    def graph_candidates(raw):
        return json.loads(Validator._graph_candidate_json(raw))

    def validate(self, raw=None):
        raw = self.inputs if raw is None else raw
        require(set(raw) == set(self.inputs), 'raw input closure mismatch')
        models = helper.source_model(raw['source']); frames, branches = conditional_model(raw['source'])
        depths, depth = {}, 0
        for number, original in enumerate(raw['source'].splitlines(), 1):
            structural = re.sub(r'\"(?:\\.|[^\"\\])*\"', '\"\"', original)
            structural = re.sub(r'//.*$', '', structural)
            depths[number] = depth
            depth += structural.count('{') - structural.count('}')
        require(depths[INACTIVE] == depths[ACTIVE] == 1 and depths[28427] == depths[28369] == 0, 'wrong declaration lexical brace/function depth')
        source = models[INACTIVE]; active_source = models[ACTIVE]
        require(source['text'].strip() == self.row['signature'], 'inactive immutable declaration signature mismatch')
        declaration = re.search(r'\b(public)\s+(static)\s+(func)\s+(\w+)\(', source['text'])
        require(declaration is not None and declaration.groups() == ('public', 'static', 'func', NAME), 'inactive source declaration fields mismatch')
        require(source['scopes'] == active_source['scopes'] == [{'kind': 'extension', 'target': 'SwiftUI.WidgetBundleBuilder', 'line': 28427, 'depth': 1}], 'exact full source owner mismatch')
        require(models[28427]['text'] == self.anchor_models[28427]['text'], 'owner source declaration changed')
        require(branches[INACTIVE] == [{'ifLine': 28480, 'branchLine': 28487, 'kind': 'else', 'condition': CONDITION}], 'inactive exact nested conditional identity mismatch')
        require(branches[ACTIVE] == [{'ifLine': 28480, 'branchLine': 28480, 'kind': 'if', 'condition': CONDITION}], 'active exact nested conditional identity mismatch')
        frame = frames[28480]
        require(frame == {'ifLine': 28480, 'condition': CONDITION, 'parentIfLines': [], 'branches': [{'kind': 'if', 'line': 28480, 'expression': CONDITION}, {'kind': 'else', 'line': 28487, 'expression': None}], 'endifLine': 28494}, 'exact full conditional frame mismatch')
        counterpart = re.sub(r'@inline\((?:__always|always)\)\s*|@inlinable\s*', '', source['text'])
        require(re.sub(r'@inline\((?:__always|always)\)\s*|@inlinable\s*', '', active_source['text']) == counterpart, 'active counterpart declaration mismatch')
        declarations = [n for n in range(28481,28494) if re.search(r'\bfunc\s+' + NAME + r'\(', models[n]['text'])]
        require(declarations == [ACTIVE, INACTIVE], 'conditional declaration cardinality mismatch')
        entities = helper.entities(raw['index'])
        require(not [e for e in entities if e['line'] == INACTIVE], 'inactive raw entity cardinality mismatch')
        active = [e for e in entities if e['line'] == ACTIVE]
        require(len(active) == 1, 'active raw entity cardinality mismatch')
        member = active[0]
        require(member['name'] == NAME + '(_:)' and member['kind'] == 'source.lang.swift.decl.function.method.static' and member.get('effective_access') == 'source.decl.effective_access.public' and not member.get('is_implicit'), 'active member kind/access mismatch')
        require(member['sourcekitContext'] and len(member['sourcekitContext']) == 1 and member['sourcekitContext'][0]['name'] == OWNER[0] and member['sourcekitContext'][0]['kind'] == 'source.lang.swift.decl.extension.struct' and member['sourcekitContext'][0]['line'] == 28427, 'active raw full owner mismatch')
        anchors = [e for e in self.anchor_entities if e['line'] == ACTIVE]
        require(len(anchors) == 1 and member == anchors[0], 'active raw identity differs from pinned index')
        graph = self.graph_candidates(raw['graph']); require(graph == self.anchor_graph, 'raw graph identities differ from pinned extraction')
        tree_map = helper.trees(raw['trees']); require(set(tree_map) == set(self.tree_usrs), 'tree USR closure mismatch')
        nominals = [e for e in entities if e['name'] == OWNER[0] and e['kind'] in {'source.lang.swift.decl.' + k for k in helper.NOMINAL.values()}]
        require(len(nominals) == 1 and nominals[0]['line'] == 28369 and nominals[0]['kind'] == 'source.lang.swift.decl.struct' and nominals[0].get('effective_access') == 'source.decl.effective_access.public' and not nominals[0].get('is_implicit'), 'nominal raw identity/cardinality mismatch')
        nominal = nominals[0]
        nominal_anchors = [e for e in self.anchor_entities if e['name'] == OWNER[0] and e['kind'] == 'source.lang.swift.decl.struct']
        require(len(nominal_anchors) == 1 and nominal == nominal_anchors[0], 'nominal raw identity differs from pinned index')
        nominal_source = models[nominal['line']]
        require(not nominal_source['scopes'] and re.search(r'\bpublic struct WidgetBundleBuilder\b', nominal_source['text']) is not None, 'full nominal source identity mismatch')
        require(nominal_source['text'] == self.anchor_models[nominal['line']]['text'], 'nominal source declaration changed')
        nominal_tree = tree_map[nominal['usr']]['children']
        require(len(nominal_tree) == 1 and nominal_tree[0]['kind'] == 'Structure' and helper.nominal_identity(nominal_tree[0]) == ('SwiftUI', OWNER), 'nominal demangle identity mismatch')
        tree_owners = {u: function_owner(tree_map[u]) for u in self.tree_usrs if u != nominal['usr']}
        tree_owners[nominal['usr']] = {'module': 'SwiftUI', 'path': OWNER, 'kind': 'struct'}
        offset = len(('\n'.join(raw['source'].splitlines()[:INACTIVE-1]) + '\n').encode()) + len(source['text'][:source['text'].index(NAME)].encode())
        require(offset == 1605000, 'inactive declaration byte offset mismatch')
        request_identity(raw['cursorRequest'], 'cursorinfo', self.interface['path'], self.sdk, self.target, offset)
        request_identity(raw['indexRequest'], 'indexsource', self.interface['path'], self.sdk, self.target)
        require(raw['cursorResponse'].strip() == '{\n  key.internal_diagnostic: "Unable to resolve cursor info."\n}', 'cursor raw diagnostic/USR cardinality mismatch')
        require(raw['probeSource'] == '#if ' + frame['condition'] + '\nprint("selected=InlineAlways")\n#else\nprint("selected=else")\n#endif\n', 'probe/source condition binding mismatch')
        processes = json.loads(raw['processResults'])
        require(set(processes) == {'compile', 'run', 'version'}, 'process result closure mismatch')
        require(processes['compile']['argv'] == self.compile_argv and processes['compile']['cwd'] == str(SCRATCH), 'actual compile invocation identity mismatch')
        require(processes['compile']['exitCode'] == 0 and processes['compile']['stdout'] == processes['compile']['stderr'] == '', 'actual compiler process failure/output mismatch')
        require(processes['run']['argv'] == [str(SCRATCH/'branch-probe')] and processes['run']['cwd'] == str(SCRATCH), 'actual probe invocation identity mismatch')
        require(processes['run']['exitCode'] == 0 and processes['run']['stdout'] == 'selected=InlineAlways\n' and processes['run']['stderr'] == '', 'actual probe result mismatch')
        require(processes['version']['argv'] == [str(self.swiftc), '-target', self.target, '--version'] and processes['version']['exitCode'] == 0 and processes['version']['stderr'] == 'swift-driver version: 1.168.6 ' and re.sub(r'^swift-driver version: [0-9.]+ ', '', processes['version']['stdout'].strip()) == self.link['toolchainEvidence']['compiler']['version'], 'actual compiler version mismatch')
        require(raw['processResults'] == self.process_anchor, 'process results differ from actual captured subprocess output')
        for key, expected in self.pins.items():
            # Same immutable byte object was already checked against immutable836
            # during construction; alternate byte objects always receive SHA checks.
            if key in raw and raw[key] is not self.inputs[key]:
                require(digest(raw[key]) == expected, 'pinned raw input bytes mismatch: ' + key)
        require(digest(raw['trees']) == digest(self.inputs['trees']), 'actual demangle bytes mismatch')
        require(digest(helper.DEMANGLE.read_bytes()) == self.pins['demangler'], 'demangler pin mismatch')
        return copy.deepcopy({'key': ['SwiftUI', self.row['interface'], INACTIVE, NAME], 'status': 'exact-inactive-compiler-branch', 'ownerPath': OWNER, 'module': 'SwiftUI', 'kind': 'static-func', 'access': 'public', 'signature': source['text'].strip(), 'sourceScopes': source['scopes'], 'conditionalFrame': frame, 'inactiveBranchPath': branches[INACTIVE], 'activeBranchPath': branches[ACTIVE], 'activeLine': ACTIVE, 'activeSource': active_source['text'].strip(), 'activeRawEntity': member, 'nominalRawEntity': nominal, 'nominalSource': nominal_source, 'inactiveRawEntityCount': 0, 'cursorDiagnostic': 'Unable to resolve cursor info.', 'cursorOffset': offset, 'symbolGraphCandidates': graph, 'compilerOwners': tree_owners, 'processResults': processes, 'decision': 'bounded inactive-else exclusion for exact source/compiler/target only; graph overloads remain ambiguous'})
