#!/usr/bin/env python3
import hashlib,json,subprocess,time
from pathlib import Path
P=Path(__file__).resolve().parent
TOOL=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend')
SDK=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
def binding(p):
 return {'path':str(p),'sha256':'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
def capture(stem,argv,inputs):
 out=P/(stem+'.stdout');err=P/(stem+'.stderr');start=time.time()
 with out.open('wb') as o,err.open('wb') as e:
  try:
   proc=subprocess.run(argv,cwd=P,stdout=o,stderr=e,timeout=120)
   code=proc.returncode;timeout=False
  except subprocess.TimeoutExpired:code=None;timeout=True
 receipt={'argv':argv,'cwd':str(P),'exitCode':code,'timedOut':timeout,'elapsedSeconds':time.time()-start,'tool':binding(TOOL),'inputs':[binding(p) for p in inputs],'stdout':binding(out),'stderr':binding(err)}
 (P/(stem+'.receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n');print(stem,code,timeout,flush=True)

if __name__ == '__main__':
    import shlex
    P=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/destructor-api-eligibility-proof/arm64-v2')
    P.mkdir(parents=True,exist_ok=True)
    for module in ['SwiftUICore','SwiftUI']:
        source=SDK/f'System/Library/Frameworks/{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface'
        header=shlex.split(source.read_text().splitlines()[2].split(': ',1)[1])
        flags=[];i=0
        while i < len(header):
            flag=header[i]
            if flag in {'-target','-target-variant','-target-arch-variant'}:
                if flag == '-target': flags += ['-target','arm64-apple-macosx27.0']
                i += 2
            else: flags.append(flag);i += 1
        capture(module+'-arm64',[str(TOOL),'-dump-ast','-parse-as-library','-sdk',str(SDK)]+flags+[str(source)],[source])
