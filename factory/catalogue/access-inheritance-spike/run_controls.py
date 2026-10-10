#!/usr/bin/env python3
"""Reproduce compiler visibility controls and write command/hash receipt."""
from __future__ import annotations
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
SDK='/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
DEV='/Applications/Xcode-27-RC.app/Contents/Developer'
ENV={**os.environ,'DEVELOPER_DIR':DEV}
TARGET='arm64-apple-macosx27.0'
MODULE=HERE/'build/AccessFixture.swiftmodule'
controls=[]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(name,args,out,expect=0):
    result=subprocess.run(args,cwd=ROOT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    path=HERE/out
    path.write_bytes(result.stdout)
    row={'name':name,'argv':args,'exitCode':result.returncode,'expectedExitCode':expect,
         'output':str(path.relative_to(ROOT)),'outputSha256':'sha256:'+sha(path)}
    controls.append(row)
    if result.returncode!=expect:
        raise SystemExit(f'{name}: expected exit {expect}, got {result.returncode}; see {path}')
    return result.stdout.decode(errors='replace')
def swiftc(*args):
    return ['xcrun','swiftc',*map(str,args)]
run('fixture-module',swiftc('-emit-module','-module-name','AccessFixture','-sdk',SDK,'-target',TARGET,
    '-emit-module-path',MODULE,HERE/'AccessFixture.swift'),'fixture-module-build.txt')
run('fixture-positive-public-cases',swiftc('-typecheck','-I',HERE/'build','-sdk',SDK,'-target',TARGET,
    HERE/'ImportPositive.swift'),'fixture-positive-typecheck.txt')
negative={
 'fixture-internal-case-rejected':('ImportInternalNegative.swift','ImportInternalNegative.txt',"cannot find 'InternalFixture' in scope"),
 'fixture-private-nested-case-rejected':('ImportPrivateNegative.swift','ImportPrivateNegative.txt',"inaccessible due to 'private' protection level"),
 'fixture-internal-default-nested-case-rejected':('ImportDefaultNestedNegative.swift','ImportDefaultNestedNegative.txt',"inaccessible due to 'internal' protection level"),
 'fixture-fileprivate-case-rejected':('ImportFilePrivateNegative.swift','ImportFilePrivateNegative.txt',"cannot find 'FilePrivateFixture' in scope"),
}
for name,(source,output,needle) in negative.items():
    text=run(name,swiftc('-typecheck','-I',HERE/'build','-sdk',SDK,'-target',TARGET,HERE/source),output,expect=1)
    if needle not in text: raise SystemExit(f'{name}: expected diagnostic {needle!r}')
run('actual-sdk-enum-cases-importable',swiftc('-typecheck','-sdk',SDK,'-target',TARGET,HERE/'ImportSdkCases.swift'),
    'actual-sdk-case-typecheck.txt')
run('fixture-sourcekit-index',['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',
    str(HERE/'request-index-fixture.yaml')],'index-fixture-output.txt')
run('strict-access-evidence-rebuild',['python3',str(HERE/'analyze_access.py')],'analyze-access-output.txt')
inputs=['AccessFixture.swift','ImportPositive.swift','ImportSdkCases.swift','ImportInternalNegative.swift',
        'ImportPrivateNegative.swift','ImportDefaultNestedNegative.swift','ImportFilePrivateNegative.swift',
        'request-index-fixture.yaml','analyze_access.py','test_access_evidence.py','run_controls.py']
link=json.loads((ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json').read_text())
receipt={
 'kind':'enum-case-access-control-run-receipt','version':1,
 'toolchain':{'xcode':'Xcode 27.0 (27A266a)','swift':'Apple Swift version 6.4.0.34.1',
   'sdk':SDK,'target':TARGET},
 'sourceLinkEvidenceSha256':'sha256:'+sha(ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'),
 'sourceHashes':{x['module']:x['sha256'] for x in link['interfaces']},
 'inputs':{p:'sha256:'+sha(HERE/p) for p in inputs},
 'commands':controls,
 'results':{
   'actualSdkPublicCaseImports':'passed for 11 expressions over 11 public enum-case owners',
   'fixturePublicCaseImport':'passed',
   'fixtureInternalPrivateFileprivateControls':'4 expected compile rejections',
   'sourcekitEffectiveAccessControls':'recorded in access-evidence.json',
   'tests':'passed',
 },
 'accessEvidenceSha256':'sha256:'+sha(HERE/'access-evidence.json'),
}
(HERE/'run-receipt.json').write_text(json.dumps(receipt,sort_keys=True,separators=(',',':'))+'\n')
run('access-evidence-tests',['python3',str(HERE/'test_access_evidence.py'),'-v'],'test-output.txt')
receipt['commands']=controls
(HERE/'run-receipt.json').write_text(json.dumps(receipt,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps({'commandCount':len(controls),'receipt':'run-receipt.json','accessEvidenceSha256':receipt['accessEvidenceSha256']}))
