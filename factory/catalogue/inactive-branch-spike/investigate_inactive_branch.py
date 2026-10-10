#!/usr/bin/env python3
"""Fresh actual compiler capture, independent row reconstruction & raw fault replay."""
import copy
import json
import re
from pathlib import Path
from exact_inactive_validator import Validator, HERE, ROOT, LINK, HELPER, helper, digest, require


def raw_record(raw, usr, field=None, changed=None, duplicate=False, inactive=False, implicit=False):
    token = 'key.usr: ' + json.dumps(usr) + ','
    pattern = re.compile(r'(?m)^( +)key\.kind: source\.lang\.swift\.decl\.[^\n]+\n\1key\.name: [^\n]+\n\1' + re.escape(token))
    matches = list(pattern.finditer(raw)); require(len(matches) == 1, 'fault raw declaration identity mismatch')
    match = matches[0]; indent = match[1][:-2]; begin = raw.rfind(indent + '{\n', 0, match.start())
    closed = re.search(r'(?m)^' + re.escape(indent) + r'\},?', raw[match.end():]); require(closed is not None, 'fault record close absent')
    end = match.end() + closed.end(); block = raw[begin:end]; altered = block
    if field:
        fields = list(re.finditer(r'(?m)^' + re.escape(indent + '  ') + r'key\.' + re.escape(field) + r': ([^\n]+)$', block)); require(len(fields) == 1, 'fault field cardinality mismatch')
        found = fields[0]; value = json.dumps(changed) if found[1].startswith('"') else str(changed)
        altered = block[:found.start(1)] + value + (',' if found[1].endswith(',') else '') + block[found.end(1):]
    if inactive:
        altered = re.sub(r'(?m)^(' + re.escape(indent + '  ') + r'key\.line: )28484,', r'\g<1>28491,', altered)
    if implicit:
        altered = altered.replace(indent + '{\n', indent + '{\n' + indent + '  key.is_implicit: 1,\n', 1)
    return raw[:begin] + (block + '\n' + altered if duplicate else altered) + raw[end:]


def run(output=HERE/'inactive-branch-evidence.json'):
    validator = Validator(); row = validator.validate(); controls = []
    def fault(label, key, changed):
        require(validator.validate() == row, 'positive production baseline failed')
        original = validator.inputs[key]; require(changed != original and digest(changed) != digest(original), 'fault bytes unchanged')
        candidate = dict(validator.inputs); candidate[key] = changed
        try:
            validator.validate(candidate)
        except ValueError as error:
            controls.append({'fault': label, 'rawInput': key, 'baselineAccepted': True, 'beforeSha256': digest(original), 'afterSha256': digest(changed), 'bytesDiffer': True, 'rejected': True, 'rejection': str(error)})
        else:
            raise ValueError('production guard accepted raw fault: ' + label)
    source = validator.inputs['source']
    def source_line(label, number, transform):
        lines = source.splitlines(keepends=True); lines[number-1] = transform(lines[number-1]); fault(label, 'source', ''.join(lines))
    fault('unbound-appended-source-bytes', 'source', source + '\n// altered input bytes\n')
    for label, old, new in [('name', 'buildLimitedAvailability', '__WrongName'), ('access', 'public static func', 'internal static func'), ('kind', 'static func', 'static var'), ('static', 'public static func', 'public func'), ('signature', 'any SwiftUI.Widget)', 'some SwiftUI.Widget)')]:
        source_line('inactive-source-' + label, 28491, lambda s,o=old,n=new:s.replace(o,n,1))
    source_line('active-counterpart-signature', 28484, lambda s:s.replace('any SwiftUI.Widget)', 'some SwiftUI.Widget)',1))
    source_line('extension-full-owner', 28427, lambda s:s.replace('SwiftUI.WidgetBundleBuilder','SwiftUI.WrongOwner',1))
    source_line('nominal-source-owner', 28369, lambda s:s.replace('WidgetBundleBuilder','WrongOwner',1))
    source_line('nominal-source-access', 28369, lambda s:s.replace('public struct','internal struct',1))
    source_line('wrong-condition', 28480, lambda s:s.replace('$InlineAlways','$OtherFlag',1))
    source_line('missing-else', 28487, lambda s:'\n')
    source_line('duplicate-else', 28494, lambda s:'  #else\n' + s)
    source_line('wrong-endif-nesting', 28494, lambda s:'  #if true\n' + s)
    source_line('nested-condition-identity', 28488, lambda s:'  #if true\n' + s)
    source_line('branch-declaration-cardinality', 28485, lambda s:validator.anchor_models[28484]['text'] + '\n')
    active = row['activeRawEntity']; index = validator.inputs['index']
    for field, changed in [('line',28483),('name','wrongFunction(_:)'),('usr','s:7SwiftUI9WrongTypeV'),('kind','source.lang.swift.decl.function.method.instance'),('effective_access','source.decl.effective_access.private')]:
        fault('active-raw-' + field,'index',raw_record(index,active['usr'],field,changed))
    for label, kwargs in [('duplicate',{'duplicate':True}),('implicit-duplicate',{'duplicate':True,'implicit':True}),('unexpected-inactive-entity',{'duplicate':True,'inactive':True}),('changed-name-duplicate',{'duplicate':True,'field':'name','changed':'wrongFunction(_:)'}),('changed-kind-duplicate',{'duplicate':True,'field':'kind','changed':'source.lang.swift.decl.function.method.instance'})]:
        fault(label,'index',raw_record(index,active['usr'],**kwargs))
    fault('raw-owner-path','index',raw_record(index,active['sourcekitContext'][0]['usr'],'name','WrongOwner'))
    fault('nominal-raw-duplicate','index',raw_record(index,row['nominalRawEntity']['usr'],duplicate=True))
    for key in ('cursorRequest','indexRequest'):
        for label, old, new in [('source','key.sourcefile: "','key.sourcefile: "/wrong/'),('target',validator.target,'x86_64-apple-macosx27.0'),('module','"-module-name", "SwiftUI"','"-module-name", "WrongModule"'),('sdk',validator.sdk, '/wrong/sdk')]:
            fault(key + ':' + label,key,validator.inputs[key].replace(old,new,1))
    fault('cursor-offset','cursorRequest',validator.inputs['cursorRequest'].replace('1605000','1605001',1))
    fault('cursor-usr-cardinality','cursorResponse',validator.inputs['cursorResponse'].replace('key.internal_diagnostic:', 'key.usr: "s:fake",\n  key.internal_diagnostic:',1))
    fault('cursor-diagnostic','cursorResponse',validator.inputs['cursorResponse'].replace('Unable to resolve cursor info.','wrong diagnostic',1))
    graph_raw = validator.inputs['graph']
    for ordinal, candidate in enumerate(row['symbolGraphCandidates']):
        usr = candidate['identifier']['precise']; token = '"precise":' + json.dumps(usr)
        require(graph_raw.count(token) == 1, 'fault graph raw identity cardinality mismatch')
        position = graph_raw.index(token); begin = graph_raw.rfind('{"kind":{"identifier":', 0, position)
        original_symbol, end = json.JSONDecoder().raw_decode(graph_raw, begin)
        require(original_symbol['identifier']['precise'] == usr, 'fault graph raw symbol boundary mismatch')
        for label, transform in [('usr',lambda s:s['identifier'].__setitem__('precise','s:fake')),('access',lambda s:s.__setitem__('accessLevel','private')),('kind',lambda s:s['kind'].__setitem__('identifier','swift.method')),('owner',lambda s:s.__setitem__('pathComponents',['WrongOwner','buildLimitedAvailability(_:)'])),('parameter-signature',lambda s:s['functionSignature']['parameters'][0]['declarationFragments'][0].__setitem__('spelling','wrongParameter'))]:
            altered = copy.deepcopy(original_symbol); transform(altered)
            fault('graph' + str(ordinal) + ':' + label, 'graph', graph_raw[:begin] + json.dumps(altered,separators=(',',':')) + graph_raw[end:])
        fault('graph' + str(ordinal) + ':duplicate', 'graph', graph_raw[:end] + ',' + graph_raw[begin:end] + graph_raw[end:])
    for label, old, new in [('owner','kind=Identifier, text="WidgetBundleBuilder"','kind=Identifier, text="WrongOwner"'),('module','kind=Module, text="SwiftUI"','kind=Module, text="SwiftUICore"'),('kind','kind=Static\n','kind=Variable\n'),('name','kind=Identifier, text="buildLimitedAvailability"','kind=Identifier, text="WrongName"')]:
        fault('tree:' + label,'trees',validator.inputs['trees'].replace(old,new,1))
    fault('probe-source-condition','probeSource',validator.inputs['probeSource'].replace('$InlineAlways','$OtherFlag',1))
    results = json.loads(validator.inputs['processResults'])
    for stage, field, changed in [('compile','exitCode',1),('compile','argv',['/wrong/compiler']),('compile','stdout','unexpected output'),('run','exitCode',1),('run','stdout','selected=else\n'),('run','stderr','runtime failure'),('version','stdout','wrong version')]:
        altered = copy.deepcopy(results); altered[stage][field] = changed; fault('actual-process:' + stage + ':' + field,'processResults',json.dumps(altered,sort_keys=True,separators=(',',':'))+'\n')
    for key in ('tool:compiler','tool:sourcekitd','tool:sourcekitLsp','tool:demangler'):
        original = validator.inputs[key]; fault('actual-tool-bytes:' + key,key,bytes([original[0] ^ 1]) + original[1:])
    snapshots = {'probeSource':'inline-always-conditional-probe.swift','processResults':'actual-process-results-v2.json','trees':'swift-demangle-inactive-expand-v2.txt'}
    inputs = {key:{'path':path,'sha256':validator.pins[key]} for key,path in validator.paths.items()}
    for key, filename in snapshots.items():
        path = HERE/filename; data = validator.inputs[key]; path.write_text(data); inputs[key] = {'path':str(path),'sha256':digest(data)}
    for stage, result in results.items():
        for stream in ('stdout','stderr'):
            path = HERE/('actual-' + stage + '-' + stream + '-v2.txt'); path.write_text(result[stream]); inputs[stage + ':' + stream] = {'path':str(path),'sha256':digest(path.read_bytes())}
    for key,path in [('immutable836',LINK),('frozenParserHelper',HELPER),('validator',HERE/'exact_inactive_validator.py'),('investigator',Path(__file__)),('test',HERE/'test_inactive_branch.py')]:
        inputs[key] = {'path':str(path),'sha256':digest(path.read_bytes())}
    inputs['demangler'] = {'path':str(helper.DEMANGLE),'sha256':validator.pins['demangler'],'command':validator.demangle_command}
    payload = {'kind':'f1-inactive-branch-investigation','version':2,'status':'review-only-exact-inactive-compiler-branch','method':'independent immutable836, pinned full SDK lexical/conditional/nominal model, active raw entity plus inactive raw zero & cursor diagnostic, both exact ambiguous raw graph signatures, fresh strict compiler trees & real compile/run/version subprocess captures','resolution':row,'inputs':inputs,'controls':controls,'toolchain':validator.link['toolchainEvidence'],'lineage':{'prior':'lineage-v1/inactive-branch-evidence.json','priorSha256':digest((HERE/'lineage-v1/inactive-branch-evidence.json').read_bytes()),'role':'historical only; former claim-based guard superseded'}}
    output.write_text(json.dumps(payload,sort_keys=True,separators=(',',':'))+'\n');return payload


if __name__ == '__main__':
    result=run();print(json.dumps({'key':result['resolution']['key'],'rawFaultsRejected':len(result['controls']),'status':result['status']},sort_keys=True))
