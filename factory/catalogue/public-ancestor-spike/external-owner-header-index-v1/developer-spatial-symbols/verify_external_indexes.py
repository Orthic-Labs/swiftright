#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re, shlex
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[4]; SDK=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'); TARGET='arm64-apple-macosx27.0'; LINK=ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'; EXPECTED_LINK='sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
SOURCES={'DeveloperToolsSupport':SDK/'System/Library/Frameworks/DeveloperToolsSupport.framework/Versions/A/Modules/DeveloperToolsSupport.swiftmodule/arm64e-apple-macos.swiftinterface','Spatial':SDK/'usr/lib/swift/Spatial.swiftmodule/arm64e-apple-macos.swiftinterface','Symbols':SDK/'System/Library/Frameworks/Symbols.framework/Versions/A/Modules/Symbols.swiftmodule/arm64e-apple-macos.swiftinterface','CoreFoundation':SDK/'usr/lib/swift/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftinterface'}
EXPECTED={'DeveloperToolsSupport':{'Preview':('source.lang.swift.decl.struct','s:21DeveloperToolsSupport7PreviewV',64),'PreviewTrait':('source.lang.swift.decl.struct','s:21DeveloperToolsSupport12PreviewTraitV',126)},'Spatial':{'Size3D':('source.lang.swift.ref.struct','c:@UA@SPSize3D',None)},'Symbols':{'WiggleSymbolEffect':('source.lang.swift.decl.struct','s:7Symbols18WiggleSymbolEffectV',286)},'CoreFoundation':{'CGFloat':('source.lang.swift.decl.struct','s:14CoreFoundation7CGFloatV',16)}}
def sha(b):
 if isinstance(b,str): b=b.encode()
 return 'sha256:'+hashlib.sha256(b).hexdigest()
def fs(p): return sha(p.read_bytes())
def check(ok,msg):
 if not ok: raise AssertionError(msg)
def blocks(raw):
 ls=raw.splitlines(); out=[]
 for i,l in enumerate(ls):
  m=re.match(r'^(\s+)key\.kind: (source\.lang\.(?:swift|objc|c)\.[^,]+),$',l)
  if not m: continue
  ind=len(m.group(1)); end=next((j for j in range(i+1,len(ls)) if len(ls[j])-len(ls[j].lstrip())==ind-2 and ls[j].strip() in {'},','}'}),None)
  if end is None: continue
  t='\n'.join(ls[i:end+1]); one=lambda pat:(re.search(pat,t).group(1) if re.search(pat,t) else None)
  out.append({'span':[i+1,end+1],'text':t,'kind':one(r'key\.kind: ([^,\n]+)'), 'name':one(r'key\.name: "((?:[^"\\]|\\.)*)"'), 'usr':one(r'key\.usr: "([^"]+)"'), 'line':int(one(r'key\.line: (\d+)')) if one(r'key\.line: (\d+)') else None})
 return out
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--evidence',type=Path,default=HERE/'external-owner-header-index-evidence.json'); d=json.loads(ap.parse_args().evidence.read_text())
 check(d['status']=='raw-facts-only-no-eligibility-conclusion','status'); check(d['immutableLink']['sha256']==EXPECTED_LINK and fs(LINK)==EXPECTED_LINK,'immutable link')
 check({m['module'] for m in d['modules']}==set(SOURCES),'module set')
 for m in d['modules']:
  n=m['module']; src=SOURCES[n]; check(m['source']['sha256']==fs(src),'source hash '+n); check(m['source']['bytes']==src.stat().st_size,'source bytes '+n)
  h=m['headers']; lines=src.read_text(errors='strict').splitlines(); main=[x for x in lines if x.startswith('// swift-module-flags:')]; ign=[x for x in lines if x.startswith('// swift-module-flags-ignorable:')]; check(h['mainRaw']==main[0] and h['ignorableRaw']==ign[0],'header rows '+n)
  check(h['productionTarget']==TARGET,'production target '+n); args=h['compilerArgs']; check(args[-4:]==['-sdk',str(SDK),'-target',TARGET],'production compiler suffix '+n); check('-target-variant' not in args and '-target-arch-variant' not in args,'variant leaked '+n); check(any(x['flag']=='-target-variant' for x in h['removedTargetFlags']),'removed variant '+n)
  req=ROOT/m['request']['path']; pre=ROOT/m['request']['preimagePath']; check(m['request']['sha256']==fs(req) and m['request']['preimageSha256']==fs(pre),'request hash '+n); check(req.read_bytes()==pre.read_bytes(),'request preimage '+n)
  p=m['process']; check(p['exit']==0,'exit '+n); out=ROOT/p['stdout']['path']; err=ROOT/p['stderr']['path']; check(p['stdout']['sha256']==fs(out) and p['stdout']['bytes']==out.stat().st_size,'stdout '+n); check(p['stderr']['sha256']==fs(err) and p['stderr']['bytes']==err.stat().st_size,'stderr '+n); check(p['chunking']['chunks']==[] and p['stdout']['bytes']<100000000,'chunk receipt '+n)
  got=blocks(out.read_text(errors='strict')); expected=EXPECTED[n]; records=m['targetRecords']; check(records,'target records '+n)
  if n=='Spatial': check(records[0]['usr']=='c:@UA@SPSize3D' and records[0]['occurrenceCount']==len(records[0]['occurrences'])>0,'Spatial C identity'); continue
  check({r['name'] for r in records}==set(expected),'target names '+n)
  for r in records:
   kind,usr,line=expected[r['name']]; check((r['kind'],r['usr'],r['line'])==(kind,usr,line),'target identity '+n+'/'+r['name']); check(any(b['span']==r['rawBlockLineSpan'] and sha(b['text'])==r['rawBlockSha256'] for b in got),'raw block '+n+'/'+r['name']); check(r['effectiveAccess'] in {'public','unknown'},'access encoding')
 print('external-owner-header-index-v1 verification: 4 module indexes, 5 exact Swift owners, imported Spatial C identity occurrences, production target, source/request/raw/tool hashes, & raw-only status pass')
if __name__=='__main__': main()
