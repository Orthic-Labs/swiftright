#!/usr/bin/env python3
from __future__ import annotations
import datetime,hashlib,json,re,shutil,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]; HERE=Path(__file__).resolve().parent
SDK=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'); TC=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain')
ORIG=ROOT/'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols'; LINK=ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'
MODULES={
 'DeveloperToolsSupport':(SDK/'System/Library/Frameworks/DeveloperToolsSupport.framework/Versions/A/Modules/DeveloperToolsSupport.swiftmodule/arm64e-apple-macos.swiftinterface',[('Preview','s:21DeveloperToolsSupport7PreviewV'),('PreviewTrait','s:21DeveloperToolsSupport12PreviewTraitV')]),
 'Spatial':(SDK/'usr/lib/swift/Spatial.swiftmodule/arm64e-apple-macos.swiftinterface',[('Size3D','c:@UA@SPSize3D')]),
 'Symbols':(SDK/'System/Library/Frameworks/Symbols.framework/Versions/A/Modules/Symbols.swiftmodule/arm64e-apple-macos.swiftinterface',[('WiggleSymbolEffect','s:7Symbols18WiggleSymbolEffectV')]),
 'CoreFoundation':(SDK/'usr/lib/swift/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftinterface',[('CGFloat','s:14CoreFoundation7CGFloatV')]),
}
TOOLS={'xcrun':Path('/usr/bin/xcrun'),'sourcekitLsp':TC/'usr/bin/sourcekit-lsp','sourcekitd':TC/'usr/lib/sourcekitd.framework/Versions/A/sourcekitd','swiftc':TC/'usr/bin/swiftc'}
def sha(b):
 if isinstance(b,str): b=b.encode()
 return 'sha256:'+hashlib.sha256(b).hexdigest()
def fs(p):return {'path':str(p),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size}
def utc(ns):return datetime.datetime.fromtimestamp(ns/1e9,datetime.timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')
def parse(raw,names):
 out=[]
 for name,usr in names:
  matches=[]
  for m in re.finditer(r'key\.kind: ([^,\n]+),\n\s+key\.name: "'+re.escape(name)+r'",\n\s+key\.usr: "'+re.escape(usr)+r'",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)',raw): matches.append({'name':name,'usr':usr,'kind':m.group(1),'line':int(m.group(2)),'column':int(m.group(3))})
  out.append({'name':name,'usr':usr,'matchCount':len(matches),'matches':matches[:5]})
 return out
def main():
 allrows=[]
 for module,(source,names) in MODULES.items():
  src_expected=json.loads((ORIG/'external-owner-header-index-evidence.json').read_text())['modules']; expected=next(x['source']['sha256'] for x in src_expected if x['module']==module); actual=sha(source.read_bytes()); 
  if actual!=expected: raise RuntimeError(f'{module} source drift before run')
  oldreq=ORIG/'requests'/f'{module}.yaml'; req=HERE/'requests'/f'{module}.yaml'; shutil.copyfile(oldreq,req); shutil.copyfile(req,HERE/'archive/requests'/req.name)
  argv=['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(req)]
  start_ns=time.time_ns(); start=utc(start_ns)
  result=subprocess.run(argv,cwd=ROOT,capture_output=True,check=False)
  finish_ns=time.time_ns(); finish=utc(finish_ns)
  raw=HERE/'raw'/f'{module}.index.txt'; err=HERE/'raw'/f'{module}.stderr'; raw.write_bytes(result.stdout); err.write_bytes(result.stderr)
  # Receipt is written before any decode/parse.
  receipt={'module':module,'source':fs(source),'request':fs(req)|{'path':str(req)},'process':{'argv':argv,'cwd':str(ROOT),'startedAt':start,'finishedAt':finish,'startedAtEpochNs':start_ns,'finishedAtEpochNs':finish_ns,'returncode':result.returncode,'stdout':fs(raw),'stderr':fs(err)},'toolchain':{k:fs(v) for k,v in TOOLS.items()}}
  receipt['process']['stdout']['path']=str(raw); receipt['process']['stderr']['path']=str(err)
  receipt_path=HERE/'receipts'/f'{module}.receipt.json'; receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
  shutil.copyfile(source,HERE/'archive/inputs'/f'{module}.swiftinterface'); shutil.copyfile(raw,HERE/'archive/raw'/raw.name); shutil.copyfile(err,HERE/'archive/raw'/err.name)
  text=result.stdout.decode('utf-8','replace'); summary={'module':module,'returncode':result.returncode,'ownerMatches':parse(text,names),'rawBytes':len(result.stdout),'rawSha256':sha(result.stdout)}
  allrows.append({'module':module,'receipt':str(receipt_path.relative_to(ROOT)),'summary':summary})
 out={'kind':'f1-external-owner-header-index-process-v2','version':1,'status':'raw-facts-only-no-eligibility-conclusion','immutableLink':{'path':str(LINK.relative_to(ROOT)),'sha256':sha(LINK.read_bytes())},'sdk':str(SDK),'target':'arm64-apple-macosx27.0','modules':allrows,'interpretation':'Genuine subprocess receipts written before parsing; no eligibility inference.'}
 (HERE/'process-evidence-v2.json').write_text(json.dumps(out,indent=2)+'\n'); print(json.dumps(out,indent=2))
if __name__=='__main__':main()
