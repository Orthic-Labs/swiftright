from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent
PARENT=HERE.parent/'padding-window-diagnosis-build-v1'
def h(b):return hashlib.sha256(b).hexdigest()
def snapshot():return {str(p.relative_to(HERE)):p.read_bytes() for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
def verify(s):
 plan=json.loads(s['package/plan.json']);parent=json.loads((PARENT/'package/plan.json').read_text())
 main=s['package/Sources/FactoryProbe/main.swift'].decode();old=(PARENT/'package/Sources/FactoryProbe/main.swift').read_text()
 expected=old.replace('    let bridge: Bridge\n    var graph:', '    let bridge: Bridge\n    let captureLeaseNanoseconds: UInt64\n    var graph:').replace('init(_ bridge: Bridge) { self.bridge = bridge }','init(_ bridge: Bridge, captureLeaseNanoseconds: UInt64 = 10_000_000_000) { self.bridge = bridge; self.captureLeaseNanoseconds = captureLeaseNanoseconds }').replace('> 10_000_000_000 { bridge.requestQuit() }','> captureLeaseNanoseconds { bridge.requestQuit() }').replace('        let bridge = try Bridge.load','        let captureLease = try factoryCaptureLeaseNanoseconds(Array(CommandLine.arguments.dropFirst()))\n        print("FACTORY_CAPTURE_LEASE nanoseconds=\\(captureLease) source=explicit-bounded-diagnostic-option")\n        fflush(stdout)\n        let bridge = try Bridge.load').replace('let host = RendererHost(bridge)','let host = RendererHost(bridge, captureLeaseNanoseconds: captureLease)')
 if main!=expected:raise ValueError('exact lifetime-only host delta')
 lease=s['package/Sources/FactoryProbe/CaptureLease.swift'].decode()
 if 'if arguments.isEmpty { return 10_000_000_000 }' not in lease or 'guard arguments == ["--factory-capture-lease-seconds=40"] else {' not in lease or 'return 40_000_000_000' not in lease:raise ValueError('bounded explicit40/default10')
 for q in (PARENT/'package').rglob('*'):
  if q.is_file() and q.name not in ['main.swift','plan.json'] and s['package/'+str(q.relative_to(PARENT/'package'))]!=q.read_bytes():raise ValueError('unchanged witness/layout/package bytes')
 for key in ['case','manifestHash','sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','runtimePackagePath','bridgeBindings','bridgePackagePath','rendererPath','rendererSha256','compilerPath','compilerHash','executionEligible','nativeParity','frozenTupleBound']:
  if plan[key]!=parent[key]:raise ValueError('unchanged source/template/runtime/renderer authority')
 if plan['hostArguments']!=['--factory-capture-lease-seconds=40'] or plan['captureLease']['defaultSeconds']!=10 or plan['captureLease']['selectedSeconds']!=40:raise ValueError('exact prospective lease selection')
 expectedReq=dict(parent['compileRequest']);expectedReq['scratchPath']=expectedReq['scratchPath'].replace('build-diagnosis-r1','build-capture-lease-r1')
 if plan['compileRequest']!=expectedReq:raise ValueError('fresh canonical compiler request')
 bound=plan['sourceBindings'];actual={k[len('package/'):] for k in s if k.startswith('package/') and k!='package/plan.json'}
 if len(bound)!=len({r['path'] for r in bound}) or {r['path'] for r in bound}!=actual:raise ValueError('exact source membership')
 for row in bound:
  if row['sha256']!='sha256:'+h(s['package/'+row['path']]):raise ValueError('raw source binding')
 ph=h(s['package/plan.json'])
 for f in ['build-hosts-v2.ps1','preflight.ps1']:
  text=s[f].decode()
  if ph not in text or 'build-capture-lease-r1' not in text or 'build-diagnosis-r1' in text:raise ValueError('builder/preflight prospective pin')
 binding=json.loads(s['metadata/source-binding.json'])
 if binding['frozenTupleBound'] is not False or binding['historicalTemplate']['closedTupleAuthority'] is not False or binding['runtime']['sourceCommit']!=parent['runtimeSourceCommit'] or binding['renderer']['sha256']!='sha256:'+parent['rendererSha256']:raise ValueError('unfrozen source candidate reference')
 issue=s['metadata/issue-before-launch.ps1'].decode()
 if issue.index('& $preflight -Phase Launch')>issue.index('$runID=[Guid]') or "measurementStatus='pending-actual-launch-joins'" not in issue or 'measuredHostIdentity=$null;measuredClockIdentity=$null' not in issue or 'FileMode]::CreateNew' not in issue:raise ValueError('prospective issuance before launch/no fabricated measurements')
 return {'status':'passed','planSha256':ph,'sourceHash':plan['sourceHash'],'nativeActions':0,'compilerActions':0}
if __name__=='__main__':print(json.dumps(verify(snapshot()),indent=2))
