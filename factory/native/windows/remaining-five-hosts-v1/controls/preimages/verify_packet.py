"""Offline production source-closure verifier, injectable exact-byte snapshot."""
import hashlib,json
from pathlib import Path,PurePosixPath,PureWindowsPath
from factory.gate.windows_exit_admission import _production_compile_argv
ROOT=Path(__file__).resolve().parent
LABELS=('disabled','image','shapes.fill-stroke','text.bundled-font','toggle')
REMOTE=r'D:\Claude\swiftright\factory\native\windows\remaining-five-hosts-v1'

def h(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def safe(path):
 p=PurePosixPath(path)
 return bool(path) and not p.is_absolute() and '..' not in p.parts and '\\' not in path and ':' not in path and str(p)==path

def verify_package(label,snapshot):
 if label not in LABELS:raise ValueError('unknown package')
 prefix=label+'/package/'
 read=lambda path:snapshot[prefix+path]
 plan=json.loads(read('plan.json'));manifest=json.loads(read('witness.manifest.json'))
 case=read('case.json');source=read('Sources/FactoryProbe/Witness.swift')
 if plan['case']!=manifest['case'] or plan['case']['id']!=json.loads(case)['id'] or h(case)!=plan['case']['hash']:raise ValueError('canonical case join')
 if h(source)!=plan['sourceHash'] or plan['sourceHash']!=manifest['sourceHash']:raise ValueError('exact witness source join')
 if h(read('witness.manifest.json'))!=plan['manifestHash']:raise ValueError('manifest join')
 expected=set();actual={x[len(prefix):] for x in snapshot if x.startswith(prefix) and (x[len(prefix):]=='Package.swift' or x[len(prefix):].startswith('Sources/'))}
 for binding in plan['sourceBindings']:
  path=binding['path']
  if not safe(path):raise ValueError('source binding unsafe')
  if path=='Package.swift' or path.startswith('Sources/'):
   if path in expected:raise ValueError('source binding duplicate')
   expected.add(path)
  if h(read(path))!=binding['sha256']:raise ValueError('source binding raw drift')
 if actual!=expected:raise ValueError('exact host membership')
 if plan['runtimeSourceCommit']!='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b':raise ValueError('runtime commit drift')
 if h(read('runtime-source-tree.json'))!=plan['runtimeSourceTreeHash'] or h(read('runtime-source-tree.json'))!=plan['runtimeSourceTreeFileHash']:raise ValueError('runtime source tree binding')
 if h(read('runtime-source-receipt.json'))!=plan['runtimeSourceReceiptHash']:raise ValueError('runtime source receipt binding')
 rr=json.loads(read('runtime-source-receipt.json'))
 if rr['sourceCommit']!=plan['runtimeSourceCommit'] or rr['sourceTreeHash']!=plan['runtimeSourceTreeHash']:raise ValueError('runtime receipt context')
 request=plan['compileRequest'];argv=_production_compile_argv(request)
 package=str(PureWindowsPath(REMOTE)/label/'package')
 if request['packagePath']!=package or request['scratchPath']!=str(PureWindowsPath(package)/'build-v2-r1'/'scratch') or request['compilerPath']!=plan['compilerPath']:raise ValueError('exact owned request namespace')
 if plan['executionEligible'] is not False or plan['nativeParity']!='hold' or plan['frozenTupleBound'] is not False or plan['closureBinding'] is not None:raise ValueError('source-only qualification boundary')
 pins=json.loads(snapshot['dependencies/mac-v8-input-pins.json'])
 entry=next(x for x in pins['rows'] if x['block']=='swiftui.'+label)
 if h(source)!=entry['source']['sha256'] or plan['case']['hash']!=entry['case']['sha256'] or h(read('reference-witness.swift'))!=entry['witness']['sha256']:raise ValueError('v8 exact source authority')
 for binding in plan['bridgeBindings']:
  if h(snapshot['dependencies/staged-bridge-inputs-r09/'+binding['path']])!='sha256:'+binding['sha256']:raise ValueError('actual r09 bridge bytes')
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
