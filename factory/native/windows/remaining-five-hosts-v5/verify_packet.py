"""Offline verifier for source-only remaining-five successor packet."""
import hashlib,json,sys
from pathlib import Path,PurePosixPath,PureWindowsPath
sys.path.insert(0,str(Path(__file__).resolve().parents[4]))
from factory.gate.windows_exit_admission import _production_compile_argv
ROOT=Path(__file__).resolve().parent
LABELS=('disabled','image','shapes.fill-stroke','text.bundled-font','toggle')
REMOTE=r'D:\Claude\swiftright\.factory-work\hosts'
INPUTS=r'D:\Claude\swiftright\.factory-work\inputs'
WORKSPACE=r'D:\Claude\swiftright'
BUILD='build-v5-r1'

def h(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def safe(path):
 p=PurePosixPath(path)
 return bool(path) and not p.is_absolute() and '..' not in p.parts and '\\' not in path and ':' not in path and str(p)==path

def verify_reviewed_v3_controls(snapshot):
 prefix='reviewed-v3-controls/'
 pins=json.loads(snapshot[prefix+'source-pins.json'])
 if pins.get('kind')!='reviewed-padding-build-v3-control-source-pins':raise ValueError('V3 helper pin kind')
 entries=pins.get('files')
 if not isinstance(entries,list) or len(entries)!=24:raise ValueError('V3 helper pin inventory')
 expected={prefix+'source-pins.json'}
 for entry in entries:
  path=entry.get('path')
  if not isinstance(path,str) or not safe(path):raise ValueError('V3 helper path')
  full=prefix+path
  if full in expected:raise ValueError('V3 helper duplicate')
  expected.add(full)
  raw=snapshot[full]
  if h(raw)!=entry.get('sha256') or len(raw)!=entry.get('bytes'):raise ValueError('V3 helper byte drift')
 actual={name for name in snapshot if name.startswith(prefix)}
 if actual!=expected:raise ValueError('V3 helper membership drift')
 return pins

def verify_package(label,snapshot):
 if label not in LABELS:raise ValueError('unknown package')
 verify_reviewed_v3_controls(snapshot)
 prefix=label+'/package/'
 read=lambda path:snapshot[prefix+path]
 plan=json.loads(read('plan.json'));manifest=json.loads(read('witness.manifest.json'))
 case=read('case.json');source=read('Sources/FactoryProbe/Witness.swift')
 if plan['case']!=manifest['case'] or plan['case']['id']!=json.loads(case)['id'] or h(case)!=plan['case']['hash']:raise ValueError('canonical case join')
 if h(source)!=plan['sourceHash'] or plan['sourceHash']!=manifest['sourceHash']:raise ValueError('exact witness source join')
 if h(read('witness.manifest.json'))!=plan['manifestHash']:raise ValueError('manifest join')
 expected=set();all_bound=set();actual={x[len(prefix):] for x in snapshot if x.startswith(prefix) and (x[len(prefix):]=='Package.swift' or x[len(prefix):].startswith('Sources/'))}
 for binding in plan['sourceBindings']:
  path=binding['path']
  if not safe(path) or path in all_bound:raise ValueError('source binding unsafe/duplicate')
  all_bound.add(path)
  if path=='Package.swift' or path.startswith('Sources/'):
   if path in expected:raise ValueError('source binding duplicate')
   expected.add(path)
  raw=read(path)
  if h(raw)!=binding['sha256'] or len(raw)!=binding.get('bytes'):raise ValueError('source binding raw drift')
 if actual!=expected:raise ValueError('exact host membership')
 if not {'witness.manifest.json','case.json','reference-witness.swift'}.issubset(all_bound):raise ValueError('consumed metadata bindings missing')
 if plan['runtimeSourceCommit']!='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b':raise ValueError('runtime commit drift')
 if h(read('runtime-source-tree.json'))!=plan['runtimeSourceTreeHash'] or h(read('runtime-source-tree.json'))!=plan['runtimeSourceTreeFileHash']:raise ValueError('runtime source tree binding')
 if h(read('runtime-source-receipt.json'))!=plan['runtimeSourceReceiptHash']:raise ValueError('runtime source receipt binding')
 rr=json.loads(read('runtime-source-receipt.json'))
 if rr['sourceCommit']!=plan['runtimeSourceCommit'] or rr['sourceTreeHash']!=plan['runtimeSourceTreeHash']:raise ValueError('runtime receipt context')
 if plan['runtimePackagePath']!=r'D:\Claude\swiftright\.factory-work\runtime-stage\runtime':raise ValueError('exact workspace runtime namespace')
 if plan['runtimeVerifierHash']!=h(snapshot['shared/verify-runtime-source.ps1'])[7:]:raise ValueError('runtime verifier raw binding')
 request=plan['compileRequest'];argv=_production_compile_argv(request)
 package=str(PureWindowsPath(REMOTE)/label/'package')
 if request['packagePath']!=package or request['scratchPath']!=str(PureWindowsPath(package)/BUILD/'scratch') or request['compilerPath']!=plan['compilerPath']:raise ValueError('exact owned request namespace')
 if plan['stage']!=WORKSPACE or plan['inputsRoot']!=INPUTS:raise ValueError('workspace input namespace')
 if plan['rendererPath']!=str(PureWindowsPath(INPUTS)/'renderer'/'swiftright_render.dll') or plan['rendererSha256']!='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93':raise ValueError('owned renderer binding')
 bridge_path=str(PureWindowsPath(INPUTS)/'SwiftRightBridge')
 if plan['bridgePackagePath']!=bridge_path or plan['bridgeSourceCommit']!='0a745ab' or plan['bridgeHeaderCommit']!='862997c':raise ValueError('owned bridge provenance')
 canonical=snapshot['dependencies/canonical-inputs-manifest.json']
 if h(canonical)!=plan['bridgeCanonicalManifestHash']:raise ValueError('canonical bridge manifest pin')
 cm=json.loads(canonical)
 expected_bridge=[{'path':b['path'].removeprefix('SwiftRightBridge/'),'sha256':b['sha256'],'bytes':b['bytes']} for b in cm['files'] if b['path'].startswith('SwiftRightBridge/')]
 if plan['bridgeBindings']!=expected_bridge or len(expected_bridge)!=10:raise ValueError('bridge membership/provenance binding')
 if plan['bridgeHeaderHash']!='12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b':raise ValueError('exact owned ABI header')
 pkg=read('Package.swift').decode('utf-8')
 escaped=lambda value:value.replace('\\','\\\\')
 if r'D:\\Claude\\sr0-r09' in pkg or escaped(bridge_path) not in pkg or escaped(plan['runtimePackagePath']) not in pkg:raise ValueError('Package.swift dependency path drift')
 main=read('Sources/FactoryProbe/main.swift').decode('utf-8')
 if r'D:\\Claude\\sr0-r09' in main or escaped(plan['rendererPath']) not in main:raise ValueError('renderer load path drift')
 if any(r'D:\Claude\sr0-r09' in str(v) for v in plan.values()):raise ValueError('stale r09 plan reference')
 if plan['executionEligible'] is not False or plan['nativeParity']!='hold' or plan['frozenTupleBound'] is not False or plan['closureBinding'] is not None:raise ValueError('source-only qualification boundary')
 pins=json.loads(snapshot['dependencies/mac-v8-input-pins.json'])
 entry=next(x for x in pins['rows'] if x['block']=='swiftui.'+label)
 if h(source)!=entry['source']['sha256'] or plan['case']['hash']!=entry['case']['sha256'] or h(read('reference-witness.swift'))!=entry['witness']['sha256']:raise ValueError('v8 exact source authority')
 ctx=plan['runtimeModuleOrigin']
 for key,path in [('receiptHash','module-origin-receipt.json'),('acceptedReplayHash','module-origin-accepted-replay.json'),('independentReviewHash','module-origin-independent-review.json')]:
  if h(snapshot['dependencies/'+path])!=ctx[key]:raise ValueError('module-origin context bytes')
 origin=json.loads(snapshot['dependencies/module-origin-receipt.json'])
 if origin['sourceCommit']!=plan['runtimeSourceCommit'] or origin['sourceTreeHash']!=plan['runtimeSourceTreeHash'] or origin['status']!='success':raise ValueError('module-origin source identity')
 expected_needs={'disabled':[],'image':['sfSymbolProvider'],'shapes.fill-stroke':['centeredContinuousRoundedStroke'],
  'text.bundled-font':['roundedFontProvider','lineLimitShaping'],'toggle':['nativeSwitchPainting']}[label]
 if plan['providerRequirements']!=expected_needs or plan['prospectiveNativeCandidate'] is not (label=='disabled'):raise ValueError('provider boundary')
 return {'label':label,'case':plan['case'],'sourceHash':h(source),'planHash':h(read('plan.json')),'compileArgv':argv,
         'sourceOnly':True,'providerHeld':bool(expected_needs),'qualificationGranted':False}

def snapshot():return {str(p.relative_to(ROOT)):p.read_bytes() for p in ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts}

if __name__=='__main__':
 s=snapshot();print(json.dumps([verify_package(label,s) for label in LABELS],indent=2))
