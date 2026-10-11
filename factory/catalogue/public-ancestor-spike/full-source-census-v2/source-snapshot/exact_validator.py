#!/usr/bin/env python3
"""Reconstruct cross-module identity from pinned raw inputs; never trust receipts."""
from __future__ import annotations
import copy
from functools import lru_cache
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
LINK = ROOT / 'factory/catalogue/compiler-cursor-spike/link-evidence.json'
EXPECTED_LINK = 'sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
DEMANGLE = Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle')
NOMINAL = {'Structure': 'struct', 'Class': 'class', 'Enum': 'enum', 'Protocol': 'protocol', 'Actor': 'actor'}


def digest(data):
    return 'sha256:' + hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


@lru_cache(maxsize=4)
def entities(raw):
    result, stack = [], []
    for line in raw.splitlines():
        opened = re.fullmatch(r'(\s*)\{', line)
        if opened:
            stack.append({'indent': len(opened[1]), 'fields': {}})
            continue
        closed = re.fullmatch(r'(\s*)\},?', line)
        if closed:
            while stack and stack[-1]['indent'] >= len(closed[1]):
                record = stack.pop()['fields']
                if str(record.get('kind', '')).startswith('source.lang.swift.decl.') and all(k in record for k in ('name', 'usr', 'line')):
                    record['sourcekitContext'] = [dict(p['fields']) for p in stack if p['fields'].get('kind', '').startswith('source.lang.swift.decl.')]
                    result.append(record)
            continue
        field = re.fullmatch(r'(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?),?', line)
        if field and stack and stack[-1]['indent'] + 2 == len(field[1]):
            value = field[3].removesuffix(',')
            if value.startswith('"'):
                value = json.loads(value)
            elif value.isdigit():
                value = int(value)
            require(field[2] not in stack[-1]['fields'], 'duplicate raw field')
            stack[-1]['fields'][field[2]] = value
    require(not stack, 'unterminated raw record')
    return result


@lru_cache(maxsize=4)
def source_model(raw):
    """Lexical scopes & exact conditional branch identity for every source line."""
    scopes, conditions, result, depth = [], [], {}, 0
    for number, original in enumerate(raw.splitlines(), 1):
        text = re.sub(r'//.*$', '', original).strip()
        if text.startswith('#if '):
            conditions.append({'line': number, 'if': text, 'branch': text})
        elif text.startswith(('#elseif ', '#else')):
            require(bool(conditions), 'orphan conditional branch')
            conditions[-1]['branch'] = text
        elif text == '#endif':
            require(bool(conditions), 'orphan endif')
            conditions.pop()
        result[number] = {'text': original, 'scopes': copy.deepcopy(scopes), 'conditions': copy.deepcopy(conditions)}
        extension = re.match(r'(?:public |internal |private |fileprivate |package )?extension\s+([\w.]+)', text)
        nominal = re.search(r'\b(struct|enum|class|protocol|actor)\s+(`?\w+`?)', text)
        if extension and '{' in text:
            scopes.append({'kind': 'extension', 'target': extension[1], 'line': number, 'depth': depth + 1})
        elif nominal and '{' in text:
            scopes.append({'kind': nominal[1], 'name': nominal[2].strip('`'), 'line': number, 'depth': depth + 1})
        # Braces inside literals cannot define scopes.
        structural = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
        depth += structural.count('{') - structural.count('}')
        scopes = [scope for scope in scopes if scope['depth'] <= depth]
    require(not conditions and depth == 0, 'unbalanced interface source')
    return result


def attributes(model, line):
    attrs = []
    cursor = line - 1
    while cursor > 0 and model[cursor]['text'].strip().startswith('@'):
        require(model[cursor]['conditions'] == model[line]['conditions'], 'annotation conditional mismatch')
        require(model[cursor]['scopes'] == model[line]['scopes'], 'annotation scope mismatch')
        attrs.insert(0, {'line': cursor, 'text': model[cursor]['text'].strip()})
        cursor -= 1
    originals = [a for a in attrs if a['text'].startswith('@_originallyDefinedIn')]
    parsed = []
    for attr in originals:
        match = re.fullmatch(r'@_originallyDefinedIn\(module: "(\w+)", (\w+) ([0-9.]+)\)', attr['text'])
        require(match is not None, 'invalid origin annotation')
        parsed.append(tuple(match.groups()))
    require(parsed == [('SwiftUI', 'iOS', '18.0'), ('SwiftUI', 'macOS', '15.0'), ('SwiftUI', 'tvOS', '18.0'), ('SwiftUI', 'watchOS', '11.0')], 'exact own origin annotations mismatch')
    return originals


@lru_cache(maxsize=4)
def trees(raw):
    result = {}
    for section in re.split(r'(?=Demangling for \$s)', raw):
        if not section.strip():
            continue
        lines = section.splitlines()
        header = re.fullmatch(r'Demangling for (\$s\S+)', lines[0])
        require(header is not None, 'invalid tree header')
        usr = 's:' + header[1][2:]
        require(usr not in result, 'duplicate tree')
        stack, roots, arrow = [], [], False
        for line in lines[1:]:
            if line.startswith('$s'):
                require(line.startswith(header[1] + ' ---> '), 'tree result identity mismatch')
                arrow = True
                continue
            if not line.strip():
                continue
            require(not arrow, 'trailing tree data')
            match = re.fullmatch(r'( *)kind=(\w+)(?:, text=("(?:\\.|[^"\\])*"))?(?:, index=(\d+))?', line)
            require(match is not None, 'invalid tree node')
            indent = len(match[1]); require(indent % 2 == 0, 'invalid tree indentation')
            node = {'kind': match[2], 'text': json.loads(match[3]) if match[3] else None, 'index': int(match[4]) if match[4] else None, 'children': []}
            while stack and stack[-1][0] >= indent:
                stack.pop()
            require(indent == (stack[-1][0] + 2 if stack else 0), 'tree skipped indentation')
            (stack[-1][1]['children'] if stack else roots).append(node)
            stack.append((indent, node))
        require(arrow and len(roots) == 1 and roots[0]['kind'] == 'Global', 'invalid tree root/result')
        result[usr] = roots[0]
    return result


def nominal_identity(node):
    require(node['kind'] in NOMINAL, 'expected nominal tree')
    children = node['children']; parents = [n for n in children if n['kind'] in NOMINAL or n['kind'] == 'Module']; names = [n for n in children if n['kind'] == 'Identifier']
    require(len(parents) == 1 and len(names) == 1 and len(children) == 2, 'ambiguous nominal tree')
    parent = parents[0]
    if parent['kind'] == 'Module':
        return parent['text'], [names[0]['text']]
    module, path = nominal_identity(parent)
    return module, path + [names[0]['text']]


def owner_identity(tree, name, kind, raw_kind):
    children = tree['children']; expected = {'func': 'Function', 'var': 'Variable', 'typealias': 'TypeAlias'}[kind]
    if raw_kind.endswith('.static'):
        require(len(children) == 1 and children[0]['kind'] == 'Static', 'missing exact static wrapper')
        children = children[0]['children']
    require(len(children) == 1 and children[0]['kind'] == expected, 'wrong direct member kind')
    declaration = children[0]
    identifiers = [n for n in declaration['children'] if n['kind'] == 'Identifier']
    owners = [n for n in declaration['children'] if n['kind'] == 'Extension']
    require(len(identifiers) == 1 and identifiers[0]['text'] == name and len(owners) == 1, 'wrong direct member name/owner')
    extension = owners[0]; modules = [n for n in extension['children'] if n['kind'] == 'Module']; nominals = [n for n in extension['children'] if n['kind'] in NOMINAL]
    require(len(modules) == len(nominals) == 1, 'ambiguous extension owner')
    require(all(n['kind'] in set(NOMINAL) | {'Module', 'DependentGenericSignature'} for n in extension['children']), 'unsupported extension owner tree')
    module, path = nominal_identity(nominals[0])
    return modules[0]['text'], module, path


class Validator:
    def __init__(self):
        require(digest(LINK.read_bytes()) == EXPECTED_LINK, 'immutable836 changed')
        self.link = json.loads(LINK.read_text())
        self.inputs, self.paths = {}, {}
        for interface in self.link['interfaces']:
            module = interface['module']
            for suffix, path_key, hash_key in [('source', 'path', 'sha256'), ('index', 'indexOutput', 'indexOutputSha256'), ('request', 'indexRequest', 'indexRequestSha256')]:
                path = Path(interface[path_key]); path = path if path.is_absolute() else ROOT / path
                data = path.read_bytes(); require(digest(data) == interface[hash_key], 'frozen input pin mismatch: ' + str(path))
                self.inputs[module + ':' + suffix] = data.decode(); self.paths[module + ':' + suffix] = path
        for name in ('compiler', 'sourcekitd', 'sourcekitLsp'):
            record = self.link['toolchainEvidence'][name]; path = Path(record.get('executablePath', record.get('path')))
            require(digest(path.read_bytes()) == record['sha256'], 'tool pin mismatch: ' + name)
        require(DEMANGLE.is_file(), 'missing pinned demangler')
        self.demangle_hash = digest(DEMANGLE.read_bytes())
        models = {m: source_model(self.inputs[m + ':source']) for m in ('SwiftUI', 'SwiftUICore')}
        self.rows = [r for r in self.link['rows'] if r['module'] == 'SwiftUI' and r.get('linkHoldReason') == 'enclosing-context-mismatch' and any(s['kind'] == 'extension' and s['target'].startswith('SwiftUICore.') for s in models['SwiftUI'][r['line']]['scopes'])]
        require(len(self.rows) == 33, 'expected33 immutable cross-module rows')
        self.anchor_entities = {m: entities(self.inputs[m + ':index']) for m in ('SwiftUI', 'SwiftUICore')}
        members = [self.member(r, self.anchor_entities['SwiftUI']) for r in self.rows]
        origin_names = sorted({r['context'][-1] for r in self.rows})
        origins = [e for e in self.anchor_entities['SwiftUICore'] if e['name'] in origin_names and e['kind'] == 'source.lang.swift.decl.struct']
        require(len(origins) == 6, 'expected6 raw origins')
        self.usrs = sorted({e['usr'] for e in members + origins})
        command = [str(DEMANGLE), '--expand', *['$s' + usr[2:] for usr in self.usrs]]
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
        require(not completed.stderr, 'demangle stderr')
        self.inputs['trees'] = completed.stdout
        self.command = command
        require(set(trees(completed.stdout)) == set(self.usrs), 'demangle closure mismatch')

    @staticmethod
    def member(row, raw_entities):
        # Count before access/kind filters: duplicates & conflicts must fail closed.
        candidates = [e for e in raw_entities if e['line'] == row['line'] and e['name'].strip('`').split('(', 1)[0] == row['name']]
        require(len(candidates) == 1, 'member cardinality mismatch')
        member = candidates[0]
        require(not member.get('is_implicit'), 'implicit member identity mismatch')
        prefixes = {'func': 'source.lang.swift.decl.function.', 'var': 'source.lang.swift.decl.var.', 'typealias': 'source.lang.swift.decl.typealias'}
        require(member['kind'].startswith(prefixes[row['kind']]), 'member kind mismatch')
        require(member.get('effective_access') == 'source.decl.effective_access.' + row['expectedAccess'], 'member access mismatch')
        return member

    def validate(self, raw=None):
        raw = self.inputs if raw is None else raw
        require(set(raw) == set(self.inputs), 'raw input closure mismatch')
        models = {m: source_model(raw[m + ':source']) for m in ('SwiftUI', 'SwiftUICore')}
        records = {m: entities(raw[m + ':index']) for m in models}
        tree_map = trees(raw['trees']); require(set(tree_map) == set(self.usrs), 'tree USR closure mismatch')
        evidence = []
        for row in self.rows:
            source = models['SwiftUI'][row['line']]
            require(source['conditions'] == source_model(self.inputs['SwiftUI:source'])[row['line']]['conditions'], 'member pinned conditional branch mismatch')
            require(source['text'].strip().removesuffix(' {').removesuffix(' { get }').strip() == row['signature'].strip().removesuffix(' {') or source['text'].strip().startswith(row['signature'].strip() + ' {'), 'member source signature mismatch')
            member = self.member(row, records['SwiftUI'])
            anchor = self.member(row, self.anchor_entities['SwiftUI'])
            require(member == anchor, 'raw member identity differs from immutable indexed input')
            scopes = source['scopes']; require(len(scopes) == 1 and scopes[0]['kind'] == 'extension', 'unsupported member scopes')
            scope = scopes[0]; target = scope['target'].split('.')
            require(target[0] == 'SwiftUICore' and target[1:] == row['context'], 'exact lexical owner mismatch')
            require(models['SwiftUI'][scope['line']]['conditions'] == source['conditions'], 'member extension conditional mismatch')
            extension_module, member_nominal_module, owner = owner_identity(tree_map[member['usr']], row['name'], row['kind'], member['kind'])
            require(extension_module == member_nominal_module == 'SwiftUI' and owner == target[1:], 'exact demangled member owner mismatch')
            origins = [e for e in records['SwiftUICore'] if e['name'] == target[-1] and e['kind'] in {'source.lang.swift.decl.' + k for k in NOMINAL.values()}]
            require(len(origins) == 1, 'origin cardinality mismatch')
            origin = origins[0]
            require(not origin.get('is_implicit'), 'implicit origin identity mismatch')
            require(origin['kind'] == 'source.lang.swift.decl.struct', 'origin kind mismatch')
            anchors = [e for e in self.anchor_entities['SwiftUICore'] if e['name'] == target[-1] and e['kind'] == 'source.lang.swift.decl.struct']
            require(len(anchors) == 1 and origin == anchors[0], 'raw origin identity mismatch')
            require(origin.get('effective_access') == 'source.decl.effective_access.public', 'origin access mismatch')
            nominal_source = models['SwiftUICore'][origin['line']]
            require(nominal_source['conditions'] == source_model(self.inputs['SwiftUICore:source'])[origin['line']]['conditions'], 'origin pinned conditional branch mismatch')
            require(not nominal_source['scopes'], 'wrong full nominal source path')
            declaration = re.search(r'\bpublic\s+(?:struct)\s+(`?\w+`?)', nominal_source['text'])
            require(declaration is not None and declaration[1].strip('`') == target[-1], 'nominal declaration identity mismatch')
            tree = tree_map[origin['usr']]
            require(len(tree['children']) == 1, 'ambiguous nominal root')
            require(tree['children'][0]['kind'] == 'Structure', 'origin expanded kind mismatch')
            nominal_module, nominal_path = nominal_identity(tree['children'][0])
            require(nominal_module == 'SwiftUICore' and nominal_path == target[1:], 'origin demangle full path mismatch')
            attrs = attributes(models['SwiftUICore'], origin['line'])
            require(raw['SwiftUI:source'].splitlines().count('@_exported import SwiftUICore') == 1, 'exact reexport mismatch')
            evidence.append({'key': [row['module'], row['interface'], row['line'], row['name']], 'line': row['line'], 'name': row['name'], 'signature': row['signature'], 'member': member, 'memberSource': source, 'extension': scope, 'target': '.'.join(target), 'compilerOwner': {'extensionModule': extension_module, 'nominalModule': member_nominal_module, 'fullPath': owner}, 'origin': origin, 'originSource': nominal_source, 'originallyDefinedIn': attrs, 'originModule': nominal_module, 'originFullPath': nominal_path, 'status': 'qualified-cross-module-extension-hold'})
        # Parse exact request identity, then pin every input byte. Raw mutations invoke
        # this very production predicate, with no mutation-only acceptance mode.
        for interface in self.link['interfaces']:
            module = interface['module']; request = raw[module + ':request']
            sourcefiles = re.findall(r'key.sourcefile:\s*("[^"]+")', request)
            args = re.findall(r'key.compilerargs:\s*\[([^\]]+)\]', request)
            require(sourcefiles == [json.dumps(interface['path'])] and len(args) == 1, 'request source identity mismatch')
            compilerargs = re.findall(r'"([^"]+)"', args[0])
            require(compilerargs == [interface['path'], '-sdk', self.link['toolchainEvidence']['sdk'], '-target', self.link['toolchainEvidence']['target'], '-module-name', module], 'exact compiler request identity mismatch')
            require('key.request: source.request.indexsource' in request, 'wrong request operation')
        for key, expected in self.inputs.items():
            require(digest(raw[key]) == digest(expected), 'raw byte pin mismatch: ' + key)
        require(digest(DEMANGLE.read_bytes()) == self.demangle_hash, 'demangler changed')
        return evidence
