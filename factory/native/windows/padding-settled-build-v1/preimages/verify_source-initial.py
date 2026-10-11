"""Exact source-only padding packet joins; no tool/remote/native execution."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parent
REMOTE=r'D:\Claude\swiftright\.factory-work\hosts\padding-settled'
RUNTIME=r'D:\Claude\swiftright\.factory-work\runtime-stage\runtime'
BRIDGE=r'D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge'
RENDERER=r'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'
def h(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def snapshot():return {str(p.relative_to(ROOT)):p.read_bytes() for p in ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
def verify(s):
 plan=json.loads(s['package/plan.json']);source=s['package/Sources/FactoryProbe/Witness.swift']
 if plan['runtimePackagePath']!=RUNTIME or plan['bridgePackagePath']!=BRIDGE or plan['rendererPath']!=RENDERER:raise ValueError('exact owned input namespace')
 if 'stage' in plan or plan['rendererSha256']!='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93':raise ValueError('renderer input authority')
 if plan['sourceHash']!=h(source) or plan['manifestHash']!=h(s['package/witness.manifest.json']):raise ValueError('exact witness/manifest')
 manifest=json.loads(s['dependencies/metrics-source-manifest.json'])
 for row in manifest['files']:
  if row['path'].startswith('Sources/') and h(s['package/'+row['path']])!=row['sha256']:raise ValueError('metrics host Swift byte delta')
 bindings=plan['sourceBindings'];bound=[r['path'] for r in bindings]
 actual={p[8:] for p in s if p.startswith('package/') and p!='package/plan.json'}
 if len(bound)!=len(set(bound)) or set(bound)!=actual:raise ValueError('exact host source/metadata membership')
 for row in bindings:
  if h(s['package/'+row['path']])!=row['sha256']:raise ValueError('host raw source binding')
 canonical=json.loads(s['dependencies/canonical-inputs-manifest.json'])
 if plan['bridgeCanonicalManifestHash']!=h(s['dependencies/canonical-inputs-manifest.json']):raise ValueError('canonical input receipt')
 authority={r['path'].split('/',1)[1]:r for r in canonical['files'] if r['path'].startswith('SwiftRightBridge/')}
 if len(authority)!=10 or {r['path'] for r in plan['bridgeBindings']}!=set(authority):raise ValueError('canonical bridge membership')
 for row in plan['bridgeBindings']:
  raw=s['dependencies/SwiftRightBridge/'+row['path']];record=authority[row['path']]
  if hashlib.sha256(raw).hexdigest()!=row['sha256'] or row['sha256']!=record['sha256'] or len(raw)!=record['bytes']:raise ValueError('canonical bridge bytes')
 if plan['compileRequest']!={'kind':'swiftpm-windows-gui-release/1','packagePath':REMOTE+'\\package','scratchPath':REMOTE+'\\package\\build-settled-r1\\scratch','compilerPath':plan['compilerPath'],'target':'windows-x86_64','configuration':'release'}:raise ValueError('production compile request')
 if plan['executionEligible'] is not False or plan['nativeParity']!='hold' or plan['frozenTupleBound'] is not False:raise ValueError('observational boundary')
 return {'sourceHash':h(source),'planHash':h(s['package/plan.json']),'canonicalBridgeMembers':10,'nativeActions':0}
if __name__=='__main__':print(json.dumps(verify(snapshot()),indent=2))
