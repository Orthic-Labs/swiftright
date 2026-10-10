#!/usr/bin/env python3
"""Capture exact SourceKit index responses for four pinned SDK owner modules."""
from __future__ import annotations
import argparse, hashlib, json, re, shlex, shutil, subprocess, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
TC = Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain')
LINK = ROOT / 'factory/catalogue/compiler-cursor-spike/link-evidence.json'
EXPECTED_LINK = 'sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
TARGET = 'arm64-apple-macosx27.0'
MODULES = {
    'DeveloperToolsSupport': {
        'source': SDK / 'System/Library/Frameworks/DeveloperToolsSupport.framework/Versions/A/Modules/DeveloperToolsSupport.swiftmodule/arm64e-apple-macos.swiftinterface',
        'owners': [('Preview', 'struct', 64), ('PreviewTrait', 'struct', 126)],
    },
    'Spatial': {
        'source': SDK / 'usr/lib/swift/Spatial.swiftmodule/arm64e-apple-macos.swiftinterface',
        'owners': [('Size3D', 'imported-c-identity', None)],
        'header': SDK / 'usr/include/Spatial/Structures.h',
    },
    'Symbols': {
        'source': SDK / 'System/Library/Frameworks/Symbols.framework/Versions/A/Modules/Symbols.swiftmodule/arm64e-apple-macos.swiftinterface',
        'owners': [('WiggleSymbolEffect', 'struct', 286)],
    },
    'CoreFoundation': {
        'source': SDK / 'usr/lib/swift/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftinterface',
        'owners': [('CGFloat', 'struct', 16)],
    },
}
TOOLS = {
    'swiftc': TC / 'usr/bin/swiftc',
    'sourcekitLsp': TC / 'usr/bin/sourcekit-lsp',
    'sourcekitd': TC / 'usr/lib/sourcekitd.framework/Versions/A/sourcekitd',
    'xcrun': Path('/usr/bin/xcrun'),
}

def sha(v: bytes | str) -> str:
    if isinstance(v, str): v = v.encode()
    return 'sha256:' + hashlib.sha256(v).hexdigest()
def fsha(p: Path) -> str: return sha(p.read_bytes())
def rel(p: Path) -> str: return str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)
def file_receipt(p: Path) -> dict: return {'path': str(p), 'sha256': fsha(p), 'bytes': p.stat().st_size}
def tool_receipt(p: Path) -> dict: return file_receipt(p)

def parse_headers(source: Path) -> dict:
    rows = source.read_text(encoding='utf-8', errors='strict').splitlines()
    main = [x for x in rows if x.startswith('// swift-module-flags:')]
    ign = [x for x in rows if x.startswith('// swift-module-flags-ignorable:')]
    if len(main) != 1 or len(ign) != 1: raise RuntimeError(f'header flag cardinality {source}: {len(main)}/{len(ign)}')
    return {'mainRaw': main[0], 'ignorableRaw': ign[0], 'main': shlex.split(main[0].split(':', 1)[1].strip()), 'ignorable': shlex.split(ign[0].split(':', 1)[1].strip())}

def transform(tokens: list[str]) -> tuple[list[str], list[dict], list[dict]]:
    kept=[]; removed=[]; forwarded=[]; i=0
    while i < len(tokens):
        flag=tokens[i]
        if flag in {'-target','-target-variant','-target-arch-variant'}:
            removed.append({'flag':flag,'value':tokens[i+1] if i+1 < len(tokens) else None}); i += 2; continue
        if flag == '-target-min-inlining-version' and i+1 < len(tokens):
            value=tokens[i+1]; kept += ['-Xfrontend',flag,'-Xfrontend',value]
            forwarded.append({'flag':flag,'value':value,'forwardedAs':['-Xfrontend',flag,'-Xfrontend',value]}); i += 2; continue
        if flag in {'-enable-objc-interop','-formal-cxx-interoperability-mode=off','-enable-experimental-concurrency','-strict-memory-safety','-enable-lexical-lifetimes=false','-parse-stdlib','-disable-objc-attr-requires-foundation-module','-enforce-exclusivity=unchecked'}:
            kept += ['-Xfrontend',flag]; forwarded.append({'flag':flag,'forwardedAs':['-Xfrontend',flag]})
        else: kept.append(flag)
        i += 1
    return kept, removed, forwarded

def request_text(source: Path, args: list[str]) -> str:
    return '{\n key.request: source.request.indexsource,\n key.sourcefile: ' + json.dumps(str(source)) + ',\n key.compilerargs: [ ' + ', '.join(json.dumps(x) for x in args) + ' ]\n}\n'

def record_blocks(raw: str) -> list[dict]:
    lines=raw.splitlines(); out=[]
    for i,line in enumerate(lines):
        m=re.match(r'^(\s+)key\.kind: (source\.lang\.(?:swift|objc|c)\.[^,]+),$',line)
        if not m: continue
        indent=len(m.group(1)); end=None
        for j in range(i+1,len(lines)):
            if len(lines[j])-len(lines[j].lstrip()) == indent-2 and lines[j].strip() in {'},','}'}:
                end=j; break
        if end is None: continue
        block='\n'.join(lines[i:end+1])
        def one(pattern):
            q=re.search(pattern,block); return q.group(1) if q else None
        out.append({'startLine':i+1,'endLine':end+1,'text':block,'kind':one(r'key\.kind: ([^,\n]+)'), 'name':one(r'key\.name: "((?:[^"\\]|\\.)*)"'), 'usr':one(r'key\.usr: "([^"]+)"'), 'line':int(one(r'key\.line: (\d+)')) if one(r'key\.line: (\d+)') else None, 'column':int(one(r'key\.column: (\d+)')) if one(r'key\.column: (\d+)') else None})
    return out

def target_facts(module: str, raw: str) -> list[dict]:
    blocks=record_blocks(raw); result=[]
    for name, expected_kind, expected_line in MODULES[module]['owners']:
        if expected_kind == 'imported-c-identity':
            # C-imported nominal has no Swift declaration block; preserve every exact SourceKit identity occurrence.
            found=[b for b in blocks if b['name']==name and b['kind']=='source.lang.swift.ref.struct' and b['usr']=='c:@UA@SPSize3D']
            if not found: raise RuntimeError(f'{module}.{name}: imported C identity missing')
            result.append({'name':name,'kind':'source.lang.swift.ref.struct','usr':'c:@UA@SPSize3D','occurrenceCount':len(found),'occurrences':[{'line':b['line'],'column':b['column'],'rawBlockLineSpan':[b['startLine'],b['endLine']],'rawBlockSha256':sha(b['text']),'rawBlock':b['text']} for b in found],'rawRecordStatus':'exact-imported-c-sourcekit-identity; no Swift declaration emitted'})
            continue
        found=[b for b in blocks if b['name']==name and b['kind']==f'source.lang.swift.decl.{expected_kind}' and (expected_line is None or b['line']==expected_line)]
        if len(found) != 1: raise RuntimeError(f'{module}.{name}: expected one exact record, found {len(found)}')
        b=found[0]
        result.append({'name':name,'kind':b['kind'],'usr':b['usr'],'line':b['line'],'column':b['column'],'effectiveAccess':'public' if 'key.effective_access: source.decl.effective_access.public' in b['text'] else 'unknown','rawBlockLineSpan':[b['startLine'],b['endLine']],'rawBlockSha256':sha(b['text']),'rawBlock':b['text'],'rawRecordStatus':'exact-physical-source-position-name-kind-usr'})
    return result

def summarize(raw: str) -> dict:
    blocks=record_blocks(raw); pairs=[(b['line'],b['column'],b['name'],b['kind'],b['usr']) for b in blocks]
    return {'recordDenominator':len(blocks),'publicEffectiveAccessFieldCount':raw.count('key.effective_access: source.decl.effective_access.public'),'publicAttributeFieldCount':raw.count('key.attribute: source.decl.attribute.public'),'physicalPositionNameKindUsrPairs':{'denominator':len(pairs),'unique':len(set(pairs)),'duplicatePairCount':len(pairs)-len(set(pairs))},'declarationKinds':sorted({b['kind'] for b in blocks})}

def capture(module: str, spec: dict) -> dict:
    source=spec['source']; headers=parse_headers(source)
    main, removed, forwarded=transform(headers['main']); ign, removed_i, forwarded_i=transform(headers['ignorable'])
    args=[str(source),*main,*ign,'-sdk',str(SDK),'-target',TARGET]
    req=HERE/'requests'/f'{module}.yaml'; req.write_text(request_text(source,args),encoding='utf-8')
    pre=HERE/'attempts'/f'{module}.request.preimage.yaml'; shutil.copyfile(req,pre)
    argv=['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(req)]
    started=time.time(); result=subprocess.run(argv,cwd=ROOT,capture_output=True,check=False); finished=time.time()
    raw=HERE/'raw'/f'{module}.index.txt'; err=HERE/'receipts'/f'{module}.stderr'; raw.write_bytes(result.stdout); err.write_bytes(result.stderr)
    rstdout=HERE/'attempts'/f'{module}.response.stdout'; rstderr=HERE/'attempts'/f'{module}.response.stderr'; shutil.copyfile(raw,rstdout); shutil.copyfile(err,rstderr)
    if result.returncode != 0: raise RuntimeError(f'{module} index failed exit {result.returncode}; preserved attempt')
    return {'module':module,'source':file_receipt(source),'headers':{'mainRaw':headers['mainRaw'],'ignorableRaw':headers['ignorableRaw'],'mainParsed':headers['main'],'ignorableParsed':headers['ignorable'],'removedTargetFlags':removed+removed_i,'forwardedFrontendFlags':forwarded+forwarded_i,'productionTarget':TARGET,'sdk':str(SDK),'compilerArgs':args},'request':{'path':rel(req),'preimagePath':rel(pre),'sha256':fsha(req),'preimageSha256':fsha(pre),'bytes':req.stat().st_size},'process':{'argv':argv,'cwd':str(ROOT),'exit':result.returncode,'startedAtEpoch':started,'finishedAtEpoch':finished,'stdout':file_receipt(raw)|{'path':rel(raw)},'stderr':file_receipt(err)|{'path':rel(err)},'attemptStdoutPath':rel(rstdout),'attemptStderrPath':rel(rstderr)},'summary':summarize(result.stdout.decode('utf-8',errors='strict')),'targetRecords':target_facts(module,result.stdout.decode('utf-8',errors='strict'))}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--module', choices=sorted(MODULES)); selected=ap.parse_args().module
    if fsha(LINK) != EXPECTED_LINK: raise RuntimeError('immutable link hash changed')
    out={'kind':'f1-external-owner-header-index-v1','version':1,'status':'raw-facts-only-no-eligibility-conclusion','immutableLink':{'path':rel(LINK),'sha256':fsha(LINK)},'sdk':str(SDK),'target':TARGET,'toolchain':{k:tool_receipt(v) for k,v in TOOLS.items()},'modules':[],'interpretation':'SourceKit index facts only; no public-ancestor or eligibility inference.'}
    for module,spec in MODULES.items():
        if selected and module != selected: continue
        if not spec['source'].exists(): raise RuntimeError(f'missing source {spec["source"]}')
        row=capture(module,spec)
        if 'header' in spec: row['relatedHeaders']=[file_receipt(spec['header'])|{'path':str(spec['header'])}]
        out['modules'].append(row)
    (HERE/'external-owner-header-index-evidence.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'modules':[{'module':m['module'],'exit':m['process']['exit'],'stdoutBytes':m['process']['stdout']['bytes'],'targets':[(r['name'],r['usr'],r['line']) for r in m['targetRecords']]} for m in out['modules']]},indent=2))
if __name__=='__main__': main()
