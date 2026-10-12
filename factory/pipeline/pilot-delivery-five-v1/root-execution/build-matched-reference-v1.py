"""Compile unchanged witness with minimal full-viewport Mac reference host."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--host',choices=('rounded-stroke','custom-layout','stack-overlay'),required=True);a=p.parse_args()
repo=Path('/Volumes/D/claude/swiftright');pilot=repo/'factory/pipeline/pilot-delivery-five-v1'
bindings={
 'rounded-stroke':('stack-layout/rounded-stroke-matched-scale-v1/mac-source/Sources/FactoryProbe/Witness.swift','Witness_shapes_fill_stroke','73235389c2f255b5ceea4184a356fbf0e582d91e00a6ad9887da8de68c2773c7'),
 'custom-layout':('stack-layout/custom-layout-host-v2/mac-source-matched-scale-v1/mac-source/Sources/CustomLayoutMacHost/Witness.swift','Witness_custom_layout','f032a6b2a4b1f850fcce02ed97964eb05c2bc8965feb3403db975c8da44c7ee3'),
 'stack-overlay':('stack-layout/stack-overlay-aac89-mac-v1/mac-source/Sources/StackOverlayMacHost/Witness.swift','Witness_stack_overlay','d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee')}
relative,function,expected=bindings[a.host]
scratch=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')/(a.host+'-full-viewport-r1')
packet=pilot/'root-execution'/(a.host+'-full-viewport-v1');out=packet/'build-r1'
def read(path,cap=16*1024*1024):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap
    return path.read_bytes()
def sha(data):return 'sha256:'+hashlib.sha256(data).hexdigest()
witness=read(pilot/relative);assert sha(witness)=='sha256:'+expected
template=read(pilot/'root-execution/rectangle-full-viewport-v1/FullViewportHost.swift').decode()
assert template.count('Witness_shapes_rectangle_fill()')==1
host=template.replace('Witness_shapes_rectangle_fill()',function+'()')
host=host.replace('        let app = NSApplication.shared','        let monoStartNs = DispatchTime.now().uptimeNanoseconds\n        let app = NSApplication.shared')
host=host.replace('            "kind": "factory-full-viewport-mac-observation-v1", "status": "OBSERVED",',
 '            "kind": "factory-full-viewport-mac-observation-v1", "status": "OBSERVED",\n            "monoStartNs": monoStartNs, "monoEndNs": DispatchTime.now().uptimeNanoseconds,')
scratch.mkdir();out.mkdir(parents=True)
rows=[]
for name,data,path in [('Witness.swift',witness,pilot/relative),('FullViewportHost.swift',host.encode(),packet/'FullViewportHost.swift')]:
    if name=='FullViewportHost.swift':path.write_bytes(data)
    destination=scratch/name;destination.write_bytes(data)
    assert sha(read(destination))==sha(data)
    rows.append({'path':str(path.relative_to(repo)),'internalPath':str(destination),'bytes':len(data),'sha256':sha(data)})
argv=['/usr/bin/xcrun','swiftc','-parse-as-library','-O','-j','1','-num-threads','1','-module-cache-path',str(scratch/'module-cache'),
 '-o',str(scratch/'capture-host'),str(scratch/'Witness.swift'),str(scratch/'FullViewportHost.swift')]
start=time.monotonic()
with (out/'compiler.stdout.bin').open('xb') as stdout,(out/'compiler.stderr.bin').open('xb') as stderr:
    child=subprocess.Popen(argv,stdout=stdout,stderr=stderr)
    try:code=child.wait(timeout=180)
    except subprocess.TimeoutExpired:
        child.terminate()
        try:child.wait(timeout=5)
        except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
        raise
receipt={'kind':'factory-full-viewport-mac-build-receipt-v1','host':a.host,'argv':argv,'sources':rows,
 'originalProcessPid':child.pid,'originalHandleRetained':True,'exitCode':code,'seconds':time.monotonic()-start,
 'frontendThreads':1,'maxJobs':1,'nativeActions':0,'qualified':False,
 'stdoutHash':sha(read(out/'compiler.stdout.bin')),'stderrHash':sha(read(out/'compiler.stderr.bin'))}
if code==0:receipt['executable']={'path':str(scratch/'capture-host'),'sha256':sha(read(scratch/'capture-host')),'bytes':(scratch/'capture-host').stat().st_size}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'host':a.host,'exitCode':code,'nativeActions':0}));raise SystemExit(code)
